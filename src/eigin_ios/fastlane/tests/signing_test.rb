require "minitest/autorun"
require "minitest/mock"
require "fastlane"
require "yaml"
Fastlane.load_actions
require_relative "../signing"

class SigningTest < Minitest::Test
  def setup
    @now = Time.utc(2026, 1, 1)
    @warnings = []
  end

  def certificate(expiry)
    key = OpenSSL::PKey::RSA.new(1024)
    cert = OpenSSL::X509::Certificate.new
    cert.serial = 1
    cert.version = 2
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=Apple Distribution")
    cert.public_key = key.public_key
    cert.not_before = @now - 86_400
    cert.not_after = expiry
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_der
  end

  def profile(days: 90, cert_days: 90)
    {
      "Name" => "Existing imported profile",
      "TeamIdentifier" => ["TEAM"], "ApplicationIdentifierPrefix" => ["PREFIX"],
      "Entitlements" => { "application-identifier" => "PREFIX.ai.eigin",
                          "com.apple.developer.team-identifier" => "TEAM", "get-task-allow" => false },
      "ExpirationDate" => @now + days * 86_400,
      "DeveloperCertificates" => [certificate(@now + cert_days * 86_400)],
    }
  end

  def validate(data)
    ReleaseSigning.validate(data, bundle_id: "ai.eigin", team_id: "TEAM", now: @now,
                           warn: ->(message) { @warnings << message })
  end

  def test_all_embedded_targets_for_both_environments
    %w[ai.eigin ai.eigin.dev].each do |base|
      assert_equal [base, "#{base}.widgets", "#{base}.watchkitapp", "#{base}.watchkitapp.widgets"],
                   ReleaseSigning.identifiers(base)
    end
  end

  def test_imported_profile_names_are_preserved
    assert_equal "Existing imported profile", validate(profile)
    assert_empty @warnings
  end

  def test_warning_boundary
    validate(profile(days: 30))
    assert_equal 1, @warnings.size
    @warnings.clear
    validate(profile(days: 31))
    assert_empty @warnings
  end

  def test_profile_dates_from_the_plist_parser
    data = profile(days: 30)
    data["ExpirationDate"] = data.fetch("ExpirationDate").to_datetime
    assert_equal "Existing imported profile", validate(data)
    assert_equal 1, @warnings.size
    data["ExpirationDate"] = @now.to_datetime
    assert_raises(RuntimeError) { validate(data) }
  end

  def test_certificate_expires_before_profile
    validate(profile(cert_days: 10))
    assert_match(/certificate/, @warnings.fetch(0))
    assert_raises(RuntimeError) { validate(profile(cert_days: 0)) }
  end

  def test_expired_profile_fails
    assert_raises(RuntimeError) { validate(profile(days: 0)) }
  end

  def test_missing_and_malformed_assets_fail
    data = profile
    data.delete("ExpirationDate")
    assert_raises(KeyError) { validate(data) }
    assert_raises(OpenSSL::X509::CertificateError) { validate(profile.merge("DeveloperCertificates" => ["bad"])) }
    assert_raises(RuntimeError) { validate(profile.merge("DeveloperCertificates" => [])) }
  end

  def test_wrong_team_bundle_and_development_profiles_fail
    assert_raises(RuntimeError) { validate(profile.merge("TeamIdentifier" => ["OTHER"])) }
    data = profile
    data["Entitlements"]["application-identifier"] = "PREFIX.other"
    assert_raises(RuntimeError) { validate(data) }
    assert_raises(RuntimeError) { validate(profile.merge("ProvisionedDevices" => ["device"])) }
  end

  def test_local_keychain_is_untouched
    result = ReleaseSigning.with_keychain(Object.new, isolated: false) { |options| options }
    assert_equal({}, result)
  end
  def with_environment(values)
    previous = ENV.to_h
    ENV.update(values)
    yield
  ensure
    ENV.replace(previous)
  end

  def with_fake_keychains(fail_default_restore: false)
    original = "/original/login.keychain-db"
    state = { search: [original, "/original/other.keychain-db"], default: original, events: [] }
    capture = lambda do |*args|
      value = case args[1]
              when "list-keychains" then state[:search].shelljoin
              when "find-identity" then "1) #{state.fetch(:identity)} \"Apple Distribution\""
              else state[:default].shellescape
              end
      [value, Struct.new(:success?).new(true)]
    end
    command = lambda do |*args|
      if args[1] == "list-keychains"
        state[:search] = args.drop(5)
        state[:events] << :search
      else
        return false if fail_default_restore && args.last == original
        state[:default] = args.last
        state[:events] << :default
      end
      true
    end
    create = lambda do |options|
      refute options[:add_to_search_list]
      refute options[:default_keychain]
      File.write(options[:path], "fixture")
      state[:path] = options[:path]
      state[:events] << :create
    end
    delete = lambda do |options|
      File.delete(options[:keychain_path])
      state[:events] << :delete
    end
    Open3.stub(:capture2, capture) do
      ReleaseSigning.stub(:system, command) do
        Fastlane::Actions::CreateKeychainAction.stub(:run, create) do
          Fastlane::Actions::DeleteKeychainAction.stub(:run, delete) { yield state }
        end
      end
    end
  end

  def test_real_lanes_use_readonly_match_before_build_and_check_never_uploads
    with_environment("BUNDLE_ID" => "ai.eigin", "DEVELOPMENT_TEAM" => "TEAM",
                     "MATCH_GIT_URL" => "git@example:signing.git", "MATCH_PASSWORD" => "test",
                     "ASC_KEY_ID" => "key", "ASC_ISSUER_ID" => "issuer", "ASC_KEY_PATH" => "unused") do
      ENV.delete("MATCH_GIT_PRIVATE_KEY")
      events = []
      with_fake_keychains do |keychains|
        Dir.mktmpdir do |dir|
          installed = File.join(dir, "profile.mobileprovision")
          File.write(installed, "fixture")
          ipa = File.join(dir, "Eigin.ipa")
          File.write(ipa, "fixture")
          ENV["ASC_KEY_PATH"] = installed
          signing_certificate = certificate(Time.now + 90 * 86_400)
          keychains[:identity] = OpenSSL::Digest::SHA1.hexdigest(signing_certificate).upcase
          match = lambda do |params|
            events << :match
            assert_equal "/original/login.keychain-db", keychains[:default]
            assert_equal ["/original/login.keychain-db", "/original/other.keychain-db"], keychains[:search]
            assert_equal true, params[:readonly]
            assert_equal "appstore", params[:type]
            assert_equal "main", params[:git_branch]
            assert_equal ReleaseSigning.identifiers("ai.eigin"), params[:app_identifier]
            params[:app_identifier].each { |id| ENV["sigh_#{id}_appstore_profile-path"] = installed }
          end
          parse = lambda do |_path|
            data = profile
            # The parser boundary returns one profile for each selected identifier.
            id = ReleaseSigning.identifiers("ai.eigin")[(events.count(:parsed)) % 4]
            events << :parsed
            data["Entitlements"]["application-identifier"] = "PREFIX.#{id}"
            data["ExpirationDate"] = Time.now + 90 * 86_400
            data["DeveloperCertificates"] = [signing_certificate]
            data
          end
          Fastlane::Actions::MatchAction.stub(:run, match) do
            FastlaneCore::ProvisioningProfile.stub(:parse, parse) do
              Fastlane::Actions::IsCiAction.stub(:run, false) do
                Fastlane::Actions::AppStoreConnectApiKeyAction.stub(:run, {}) do
                  Fastlane::Actions::LatestTestflightBuildNumberAction.stub(:run, 1) do
                    Fastlane::Actions::GymAction.stub(:run, ->(params) {
                      events << :gym
                      assert_equal "manual", params[:export_options][:signingStyle]
                      assert_equal 4, params[:export_options][:provisioningProfiles].size
                      assert_includes Shellwords.split(params[:xcargs]), "EIGIN_PROFILE_Eigin=Existing imported profile"
                      assert_equal [keychains.fetch(:path)], keychains[:search]
                      assert_equal keychains.fetch(:path), keychains[:default]
                      assert_includes Shellwords.split(params[:xcargs]), "OTHER_CODE_SIGN_FLAGS=--keychain #{keychains.fetch(:path)}"
                      ipa
                    }) do
                      Fastlane::Actions::PilotAction.stub(:run, ->(params) { assert_equal ipa, params[:ipa]; events << :pilot }) do
                        file = Fastlane::FastFile.new(File.expand_path("../Fastfile", __dir__))
                        file.runner.execute(:check_signing, :ios, env: "production")
                        assert_equal [:match, :parsed, :parsed, :parsed, :parsed], events
                        events.clear
                        assert_equal ipa, file.runner.execute(:archive, :ios, env: "production")
                        assert_equal [:match, :parsed, :parsed, :parsed, :parsed, :gym], events
                        refute File.exist?(keychains.fetch(:path))
                        events.clear
                        file.runner.execute(:beta, :ios, env: "production")
                        assert_equal [:match, :parsed, :parsed, :parsed, :parsed, :gym, :pilot], events
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def test_ssh_key_must_be_a_file_outside_the_checkout
    with_environment("MATCH_GIT_URL" => "git@example:signing.git", "MATCH_PASSWORD" => "test") do
      ["raw-private-key", __FILE__].each do |key|
        ENV["MATCH_GIT_PRIVATE_KEY"] = key
        error = assert_raises(RuntimeError) do
          ReleaseSigning.sync(Object.new, { bundle_id: "ai.eigin", team_id: "TEAM" }, {})
        end
        assert_match(/readable absolute file path outside/, error.message)
      end
    end
  end

  def test_missing_profile_error_identifies_the_bundle
    with_environment("MATCH_GIT_URL" => "git@example:signing.git", "MATCH_PASSWORD" => "test") do
      ENV.delete("MATCH_GIT_PRIVATE_KEY")
      ENV.delete("sigh_ai.eigin_appstore_profile-path")
      lane = Object.new
      lane.define_singleton_method(:match) { |**_options| }
      error = assert_raises(RuntimeError) do
        ReleaseSigning.sync(lane, { bundle_id: "ai.eigin", team_id: "TEAM" }, {})
      end
      assert_match(/Signing asset for ai.eigin/, error.message)
    end
  end

  def test_match_import_without_a_valid_identity_fails_before_building
    with_environment("MATCH_GIT_URL" => "git@example:signing.git", "MATCH_PASSWORD" => "test") do
      ENV.delete("MATCH_GIT_PRIVATE_KEY")
      lane = Object.new
      lane.define_singleton_method(:match) { |**_options| }
      success = Struct.new(:success?).new(true)
      Open3.stub(:capture2, ["0 valid identities found", success]) do
        error = assert_raises(RuntimeError) do
          ReleaseSigning.sync(lane, { bundle_id: "ai.eigin", team_id: "TEAM" }, { keychain_name: "/temporary/signing.keychain-db" })
        end
        assert_match(/No valid signing identity/, error.message)
      end
    end
  end

  def keychain_actions
    lane = Object.new
    lane.define_singleton_method(:create_keychain) { |**options| Fastlane::Actions::CreateKeychainAction.run(options) }
    lane.define_singleton_method(:delete_keychain) { |**options| Fastlane::Actions::DeleteKeychainAction.run(options) }
    lane
  end

  def test_isolated_keychain_restores_settings_on_success_and_failure
    [false, true].each do |fail_archive|
      with_fake_keychains do |state|
        original_search = state[:search].dup
        original_default = state[:default]
        action = lambda do
          ReleaseSigning.with_keychain(keychain_actions, isolated: true) do |options|
            assert_equal original_search, state[:search]
            assert_equal original_default, state[:default]
            ReleaseSigning.isolate_keychain(options)
            assert_equal [options.fetch(:keychain_name)], state[:search]
            assert_equal options.fetch(:keychain_name), state[:default]
            assert File.file?(options.fetch(:keychain_name))
            raise "archive failed" if fail_archive
            :exported
          end
        end
        if fail_archive
          assert_equal "archive failed", assert_raises(RuntimeError, &action).message
        else
          assert_equal :exported, action.call
        end
        assert_equal original_search, state[:search]
        assert_equal original_default, state[:default]
        refute File.exist?(state.fetch(:path))
        assert_equal [:create, :search, :default, :default, :search, :delete], state[:events]
      end
    end
  end

  def test_cleanup_failure_still_restores_search_list_and_deletes_keychain
    with_fake_keychains(fail_default_restore: true) do |state|
      original_search = state[:search].dup
      error = assert_raises(RuntimeError) do
        ReleaseSigning.with_keychain(keychain_actions, isolated: true) do |options|
          ReleaseSigning.isolate_keychain(options)
          :exported
        end
      end
      assert_match(/Cannot restore default keychain/, error.message)
      assert_equal original_search, state[:search]
      refute File.exist?(state.fetch(:path))
    end
  end

  def test_cleanup_failure_preserves_the_archive_error
    with_fake_keychains(fail_default_restore: true) do |state|
      error = assert_raises(RuntimeError) do
        ReleaseSigning.with_keychain(keychain_actions, isolated: true) do |options|
          ReleaseSigning.isolate_keychain(options)
          raise "archive failed"
        end
      end
      assert_equal "archive failed", error.message
      refute File.exist?(state.fetch(:path))
    end
  end

  def test_xcode_resolves_release_overrides_and_defaults_to_automatic_signing
    source = YAML.load_file(File.expand_path("../../project.yml", __dir__))
    Dir.mktmpdir do |root|
      targets = {}
      ReleaseSigning::TARGETS.values.flatten.each do |name|
        base = source.fetch("targets").fetch(name).fetch("settings").fetch("base")
        targets[name] = {
          "type" => "application", "platform" => "iOS",
          "settings" => { "base" => base.slice("CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE_SPECIFIER") },
        }
      end
      targets["DependencyResources"] = {
        "type" => "bundle", "platform" => "iOS",
        "settings" => { "base" => { "CODE_SIGN_IDENTITY" => "-", "GENERATE_INFOPLIST_FILE" => "YES" } },
      }
      spec = { "name" => "Fixture", "settings" => source.fetch("settings"), "targets" => targets }
      path = File.join(root, "project.yml")
      File.write(path, YAML.dump(spec))
      assert system("xcodegen", "generate", "--spec", path)
      %w[Eigin EiginDev].each do |name|
        release = { scheme: name, bundle_id: name == "Eigin" ? "ai.eigin" : "ai.eigin.dev" }
        profiles = ReleaseSigning.identifiers(release[:bundle_id]).to_h { |id| [id, "Imported #{id}'s profile"] }
        command = ["xcodebuild", "-showBuildSettings", "-project", File.join(root, "Fixture.xcodeproj"), "-target", name]
        output, status = Open3.capture2e(*command)
        assert status.success?, output
        assert_match(/^\s+CODE_SIGN_STYLE = Automatic$/, output)
        assert_includes output, "CODE_SIGN_IDENTITY = Apple Development"
        dependency_command = command.dup
        dependency_command[-1] = "DependencyResources"
        output, status = Open3.capture2e(*dependency_command, *Shellwords.split(ReleaseSigning.build_settings(release, profiles)))
        assert status.success?, output
        assert_match(/^\s+CODE_SIGN_IDENTITY = -$/, output)
        refute_match(/^\s+CODE_SIGN_STYLE = Manual$/, output)
        ReleaseSigning::TARGETS.each do |suffix, (prod_target, dev_target)|
          target = name == "Eigin" ? prod_target : dev_target
          command[-1] = target
          output, status = Open3.capture2e(*command, *Shellwords.split(ReleaseSigning.build_settings(release, profiles)))
          assert status.success?, output
          assert_match(/^\s+CODE_SIGN_STYLE = Manual$/, output)
          assert_includes output, "PROVISIONING_PROFILE_SPECIFIER = #{profiles.fetch("#{release[:bundle_id]}#{suffix}")}"
          assert_includes output, "CODE_SIGN_IDENTITY = Apple Distribution"
        end
      end
    end
  end
end
