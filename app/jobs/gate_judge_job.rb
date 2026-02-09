class GateJudgeJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 2

  def perform(application_id)
    application = GateApplication.find(application_id)
    return unless application.status == "judging"

    result = GateJudgeService.evaluate(application)
    tick = SimulationService.current_tick

    if result[:passed]
      handle_pass(application, result, tick)
    else
      handle_fail(application, result, tick)
    end
  end

  private

  def handle_pass(application, result, tick)
    town_square = Location.find_by!(name: "Town Square")

    agent_result = Agent.create_with_api_key(
      name: application.agent_name,
      description: application.agent_description,
      personality_traits: application.agent_personality_traits,
      goals: application.agent_goals,
      owner: application.owner,
      location: town_square,
      probation_until: 24.hours.from_now,
      status: "idle"
    )

    agent = agent_result[:agent]
    api_key = agent_result[:api_key]

    Sidekiq.redis { |conn| conn.set("gate:api_key:#{application.id}", api_key, ex: 3600) }

    application.update!(
      status: "passed_pending_verification",
      agent: agent,
      judge_reasoning: result[:reasoning]
    )

    EventService.append(
      event_type: "gate_application_passed",
      tick: tick,
      payload: {
        application_id: application.id,
        agent_id: agent.id,
        agent_name: application.agent_name,
        method: result[:method],
        reasoning: result[:reasoning]
      }
    )
  end

  def handle_fail(application, result, tick)
    application.update!(
      status: "failed",
      judge_reasoning: result[:reasoning]
    )

    EventService.append(
      event_type: "gate_application_failed",
      tick: tick,
      payload: {
        application_id: application.id,
        agent_name: application.agent_name,
        method: result[:method],
        reasoning: result[:reasoning]
      }
    )
  end
end
