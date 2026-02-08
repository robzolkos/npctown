require "sidekiq"
require "sidekiq-scheduler"

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  config.on(:startup) do
    SimulationService.start
    SimulationService.register_listener(MemoryService)
    SimulationService.register_listener(ConversationService)
    SimulationService.register_listener(StaminaService)
    SimulationService.register_listener(ReflectionService)
    SimulationService.register_listener(PlanService)
    SimulationService.register_listener(ResourceService)
  end

  config.on(:shutdown) do
    SimulationService.stop
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
