require "openssl"
require "open3"
require "tmpdir"
require "securerandom"
require "shellwords"
require "pathname"

# Installs and checks distribution signing assets.
module ReleaseSigning
  TARGETS = {
    "" => %w[Eigin EiginDev],
    ".widgets" => %w[EiginWidgetsExtension EiginWidgetsDevExtension],
    ".watchkitapp" => %w[EiginWatch EiginWatchDev],
    ".watchkitapp.widgets" => %w[EiginWatchWidgets EiginWatchWidgetsDev],
  }.freeze

  def self.identifiers(bundle_id)
    TARGETS.keys.map { |suffix| "#{bundle_id}#{suffix}" }
  end

  # Validates the selected profile and every certificate it authorizes, offline.
  def self.validate(profile, bundle_id:, team_id:, now: Time.now, warn:)
    entitlements = profile.fetch("Entitlements")
    prefix = profile.fetch("ApplicationIdentifierPrefix").first
    unless profile.fetch("TeamIdentifier").include?(team_id) &&
           entitlements["application-identifier"] == "#{prefix}.#{bundle_id}" &&
           entitlements["com.apple.developer.team-identifier"] == team_id &&
           !entitlements["get-task-allow"] && !profile.key?("ProvisionedDevices") &&
           !profile["ProvisionsAllDevices"]
      raise "Invalid App Store profile for #{bundle_id} / #{team_id}"
    end
    certificates = profile.fetch("DeveloperCertificates")
    raise "No signing certificate for #{bundle_id}" if certificates.empty?

    expiries = [["profile", profile.fetch("ExpirationDate").to_time]]
    certificates.each do |data|
      cert = OpenSSL::X509::Certificate.new(data.respond_to?(:string) ? data.string : data)
      raise "Signing certificate not yet valid for #{bundle_id}" if cert.not_before > now
      expiries << ["certificate", cert.not_after]
    end
    expiries.each do |kind, expiry|
      raise "Expired #{kind} for #{bundle_id}: #{expiry.utc}" if expiry <= now
      warn.call("#{kind} for #{bundle_id} expires #{expiry.utc}") if expiry <= now + 30 * 86_400
    end
    profile.fetch("Name")
  end

  # Creates a temporary signing keychain and restores the user's settings.
  def self.with_keychain(lane, isolated:)
    return yield({}) unless isolated

    search_list, status = Open3.capture2("security", "list-keychains", "-d", "user")
    raise "Cannot read keychain search list" unless status.success?
    default, status = Open3.capture2("security", "default-keychain", "-d", "user")
    raise "Cannot read default keychain" unless status.success?
    original_default = Shellwords.split(default).fetch(0)

    Dir.mktmpdir("eigin-keychain-") do |dir|
      path = File.join(dir, "release.keychain-db")
      password = SecureRandom.hex(32)
      begin
        lane.create_keychain(path: path, password: password, unlock: true,
                             default_keychain: false, add_to_search_list: false,
                             timeout: 3600, require_create: true)
        yield(keychain_name: path, keychain_password: password)
      ensure
        original_error = $!
        errors = []
        cleanups = [
          -> { raise "Cannot restore default keychain" unless system("security", "default-keychain", "-d", "user", "-s", original_default) },
          -> { raise "Cannot restore keychain search list" unless system("security", "list-keychains", "-d", "user", "-s", *Shellwords.split(search_list)) },
          -> { lane.delete_keychain(keychain_path: path) if File.exist?(path) },
        ]
        cleanups.each do |cleanup|
          cleanup.call
        rescue StandardError => error
          errors << error.message
        end
        unless errors.empty?
          raise errors.join("; ") unless original_error
          FastlaneCore::UI.error(errors.join("; "))
        end
      end
    end
  end

  # Isolates signing after match has used the user's repository credentials.
  def self.isolate_keychain(keychain)
    path = keychain.fetch(:keychain_name)
    raise "Cannot isolate keychain search list" unless system("security", "list-keychains", "-d", "user", "-s", path)
    raise "Cannot select temporary keychain" unless system("security", "default-keychain", "-d", "user", "-s", path)
  end

  def self.sync(lane, release, keychain)
    %w[MATCH_GIT_URL MATCH_PASSWORD].each do |key|
      raise "#{key} is required for release signing" if ENV.fetch(key, "").strip.empty?
    end
    key_path = ENV["MATCH_GIT_PRIVATE_KEY"]
    if key_path && !key_path.empty?
      checkout = File.realpath(File.expand_path("../../..", __dir__))
      unless Pathname.new(key_path).absolute? && File.file?(key_path) && File.readable?(key_path) &&
             !File.realpath(key_path).start_with?("#{checkout}/")
        raise "MATCH_GIT_PRIVATE_KEY must be a readable absolute file path outside the checkout"
      end
    end
    ids = identifiers(release.fetch(:bundle_id))
    lane.match(type: "appstore", readonly: true, storage_mode: "git",
               git_branch: "main", app_identifier: ids, team_id: release.fetch(:team_id), **keychain)
    identities = nil
    if keychain[:keychain_name]
      output, status = Open3.capture2("security", "find-identity", "-v", "-p", "codesigning", keychain.fetch(:keychain_name))
      identities = output.scan(/\b[0-9A-F]{40}\b/i).map(&:upcase)
      unless status.success? && !identities.empty?
        raise "No valid signing identity in temporary keychain; check the match private key format and import password"
      end
    end
    ids.to_h do |id|
      path = ENV.fetch("sigh_#{id}_appstore_profile-path", nil)
      begin
        raise "Installed profile is missing" unless path && File.file?(path)
        profile = FastlaneCore::ProvisioningProfile.parse(path)
        if identities
          matching = profile.fetch("DeveloperCertificates").any? do |data|
            cert = OpenSSL::X509::Certificate.new(data.respond_to?(:string) ? data.string : data)
            identities.include?(OpenSSL::Digest::SHA1.hexdigest(cert.to_der).upcase)
          end
          raise "Profile has no matching private key in temporary keychain" unless matching
        end
        name = validate(profile, bundle_id: id, team_id: release.fetch(:team_id),
                        warn: ->(message) { FastlaneCore::UI.important(message) })
        [id, name]
      rescue StandardError => error
        raise "Signing asset for #{id} (#{path || 'no installed path'}): #{error.message}"
      end
    end
  end

  # Supplies per-target Xcode build settings through gym's xcargs.
  def self.build_settings(release, profiles, keychain: {})
    production = release.fetch(:scheme) == "Eigin"
    settings = ["EIGIN_SIGNING_STYLE=Manual", "EIGIN_CODE_SIGN_IDENTITY=Apple Distribution"]
    TARGETS.each do |suffix, (prod_target, dev_target)|
      target = production ? prod_target : dev_target
      settings << "EIGIN_PROFILE_#{target}=#{profiles.fetch("#{release.fetch(:bundle_id)}#{suffix}")}"
    end
    if keychain[:keychain_name]
      settings << "OTHER_CODE_SIGN_FLAGS=#{["--keychain", keychain.fetch(:keychain_name)].shelljoin}"
    end
    settings.shelljoin
  end
end
