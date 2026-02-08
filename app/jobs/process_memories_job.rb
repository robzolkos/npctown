class ProcessMemoriesJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 3

  def perform(tick)
    MemoryService.process_events_into_memories(tick)
  end
end
