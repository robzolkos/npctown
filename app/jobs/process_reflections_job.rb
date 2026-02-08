class ProcessReflectionsJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 3

  def perform(tick)
    ReflectionService.generate_reflections(tick)
  end
end
