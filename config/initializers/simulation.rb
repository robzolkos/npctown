Sidekiq.configure_server do |config|
  config.on(:shutdown) do
    SimulationService.stop_timer
  end
end
