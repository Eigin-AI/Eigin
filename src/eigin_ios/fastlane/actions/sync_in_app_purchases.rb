require "net/http"
require "json"
require "yaml"

# Pushes fastlane/iap/*.yml to App Store Connect via the REST API directly —
# fastlane's own IAP interfaces are incomplete for writes.
#
# Localizations attach to a separate "version" resource, not the product
# itself; this reuses the existing one, since Apple exposes no DELETE for it.
#
# Create/update only — deletion isn't exposed for live products; remove
# retired IAPs by hand in App Store Connect.
module Fastlane
  module Actions
    class SyncInAppPurchasesAction < Action
      BASE_URL_V1 = "https://api.appstoreconnect.apple.com/v1"
      BASE_URL_V2 = "https://api.appstoreconnect.apple.com/v2"

      def self.run(params)
        token = Spaceship::ConnectAPI::Token.from(hash: params[:api_key]) ||
                Spaceship::ConnectAPI.token
        Spaceship::ConnectAPI.token = token

        app_id = find_app_id(params[:bundle_id])
        definitions = load_definitions(params[:definitions_path], params[:env])

        definitions.each do |definition|
          iap_id = upsert_product(app_id, definition)
          sync_localizations(iap_id, definition["localizations"]) if definition["localizations"]
        end
        UI.success("Synced #{definitions.size} in-app purchase(s) for #{params[:bundle_id]}")
      end

      # `product_id` is a plain string or an env -> id map; resolves to the
      # requested env's id, skipping defs that don't define one for it.
      def self.load_definitions(path, env)
        Dir.glob(File.join(path, "*.{yml,yaml}")).filter_map do |file|
          definition = YAML.load_file(file)
          product_id = definition["product_id"]
          product_id = product_id[env] if product_id.is_a?(Hash)
          next unless product_id

          definition.merge("product_id" => product_id)
        end
      end

      def self.find_app_id(bundle_id)
        app = Spaceship::ConnectAPI::App.find(bundle_id)
        UI.user_error!("No App Store Connect app found for #{bundle_id}") unless app
        app.id
      end

      # Creates or patches the product; returns its App Store Connect id.
      def self.upsert_product(app_id, definition)
        product_id = definition.fetch("product_id")
        existing = find_existing_product(app_id, product_id)
        return patch_product(existing["id"], definition) if existing

        create_product(app_id, definition)
      end

      def self.find_existing_product(app_id, product_id)
        response = request(:get, "#{BASE_URL_V1}/apps/#{app_id}/inAppPurchasesV2?filter[productId]=#{product_id}")
        response["data"]&.first
      end

      def self.create_product(app_id, definition)
        body = {
          data: {
            type: "inAppPurchases",
            attributes: {
              name: definition.fetch("reference_name"),
              productId: definition.fetch("product_id"),
              inAppPurchaseType: definition.fetch("type"),
              reviewNote: definition["review_note"],
            },
            relationships: { app: { data: { type: "apps", id: app_id } } },
          },
        }
        request(:post, "#{BASE_URL_V2}/inAppPurchases", body)["data"]["id"]
      end

      def self.patch_product(id, definition)
        body = {
          data: {
            type: "inAppPurchases",
            id: id,
            attributes: { name: definition.fetch("reference_name") },
          },
        }
        request(:patch, "#{BASE_URL_V2}/inAppPurchases/#{id}", body)
        id
      end

      # `localizations` is a locale => { name:, description: } map.
      def self.sync_localizations(iap_id, localizations)
        version_id = find_or_create_version(iap_id)
        existing = list_localizations(version_id)

        localizations.each do |locale, copy|
          match = existing.find { |l| l["attributes"]["locale"] == locale }
          match ? patch_localization(match["id"], copy) : create_localization(version_id, locale, copy)
        end
      end

      # A product has at most one editable version; multiple means something
      # needs resolving by hand — don't guess which one to touch.
      def self.find_or_create_version(iap_id)
        versions = request(:get, "#{BASE_URL_V2}/inAppPurchases/#{iap_id}/versions")["data"] || []
        case versions.size
        when 0 then create_version(iap_id)
        when 1 then versions.first["id"]
        else UI.user_error!("Multiple IAP versions exist for #{iap_id}; resolve manually in App Store Connect.")
        end
      end

      def self.create_version(iap_id)
        body = {
          data: {
            type: "inAppPurchaseVersions",
            relationships: { inAppPurchase: { data: { type: "inAppPurchases", id: iap_id } } },
          },
        }
        request(:post, "#{BASE_URL_V1}/inAppPurchaseVersions", body)["data"]["id"]
      end

      def self.list_localizations(version_id)
        request(:get, "#{BASE_URL_V1}/inAppPurchaseVersions/#{version_id}/localizations")["data"] || []
      end

      def self.create_localization(version_id, locale, copy)
        body = {
          data: {
            type: "inAppPurchaseLocalizations",
            attributes: { name: copy.fetch("name"), locale: locale, description: copy["description"] },
            relationships: { version: { data: { type: "inAppPurchaseVersions", id: version_id } } },
          },
        }
        request(:post, "#{BASE_URL_V2}/inAppPurchaseLocalizations", body)
      end

      def self.patch_localization(id, copy)
        body = {
          data: {
            type: "inAppPurchaseLocalizations",
            id: id,
            attributes: { name: copy.fetch("name"), description: copy["description"] },
          },
        }
        request(:patch, "#{BASE_URL_V2}/inAppPurchaseLocalizations/#{id}", body)
      end

      def self.request(method, url, body = nil)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
        request["Authorization"] = "Bearer #{Spaceship::ConnectAPI.token.text}"
        request["Content-Type"] = "application/json"
        request.body = body.to_json if body

        response = http.request(request)
        UI.user_error!("App Store Connect API error #{response.code}: #{response.body}") unless response.code.to_i < 300
        response.body.to_s.empty? ? {} : JSON.parse(response.body)
      end

      def self.description
        "Creates/updates in-app purchases (and their localizations) from fastlane/iap/*.yml via the App Store Connect API"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :bundle_id, description: "Bundle identifier of the target app", type: String),
          FastlaneCore::ConfigItem.new(key: :env, description: "staging | production, selects the per-env product_id", type: String),
          FastlaneCore::ConfigItem.new(key: :api_key, description: "App Store Connect API key hash", type: Hash),
          FastlaneCore::ConfigItem.new(
            key: :definitions_path,
            description: "Directory of IAP definition files",
            type: String,
            default_value: File.join(Dir.pwd, "fastlane", "iap"),
          ),
        ]
      end

      def self.is_supported?(platform)
        platform == :ios
      end
    end
  end
end
