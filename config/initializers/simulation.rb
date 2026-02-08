Sidekiq.configure_server do |config|
  config.on(:shutdown) do
    SimulationService.stop_timer
  end
end

Rails.application.config.after_initialize do
  SimulationService.register_listener(ConversationService)
end
