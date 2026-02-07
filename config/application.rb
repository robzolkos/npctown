require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module NpcTown
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    # String primary keys for prefixed KSUIDs (e.g., agt_xxx, loc_xxx)
    # ID generation is handled by the PrefixedId concern, not the database
    config.generators do |g|
      g.orm :active_record, primary_key_type: :string
      g.test_framework :minitest, spec: false, fixture: true
    end

    # Use Sidekiq for ActiveJob
    config.active_job.queue_adapter = :sidekiq
  end
end
