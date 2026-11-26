require_relative "boot"

# 使う部品だけ読み込む(#58)。Action Mailbox(メールの受け口)と Action Text は使わないので外す。
# 公開しているサーバーで、外から届く口を増やさないため
require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module NBato
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Tokyo"
    config.i18n.default_locale = :ja
    # 画像の変換(サムネイル)は使わない
    config.active_storage.variant_processor = :disabled
    # 添付(証憑など)は、ログインを確かめるコントローラーだけで出す(#27)。
    # Active Storage の道筋(/rails/active_storage/…)は、署名付きの URL を知っていればログインなしで開けるので作らない
    config.active_storage.draw_routes = false
    config.i18n.available_locales = [:ja, :en]
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
