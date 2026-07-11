require_relative "boot"

require "rails"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module StLucySignup
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true

    # No database — Google Sheets is the datastore (see SheetService).
    config.cache_store = :memory_store

    # The app only ever runs behind the Cloudflare Tunnel / localhost.
    config.hosts.clear
  end
end
