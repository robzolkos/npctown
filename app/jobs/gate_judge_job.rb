class GateJudgeJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 2

  def perform(application_id)
    # Step 9: Hybrid Judge implementation (heuristics + Grok 4.1 Fast LLM)
  end
end
