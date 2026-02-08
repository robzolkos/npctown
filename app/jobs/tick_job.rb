class TickJob
  include Sidekiq::Job

  sidekiq_options queue: :simulation, retry: 0

  def perform
    SimulationService.tick!
  end
end
