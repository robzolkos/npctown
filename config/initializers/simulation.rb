Sidekiq.configure_server do |config|
  config.on(:shutdown) do
    SimulationService.stop_timer
  end
end

Rails.application.config.after_initialize do
  SimulationService.register_listener(MemoryService)
  SimulationService.register_listener(ConversationService)

  unless Rails.env.test?
    SimulationService.start
  end
end
