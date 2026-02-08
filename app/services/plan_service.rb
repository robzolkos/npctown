class PlanService
  class PlanError < StandardError; end

  STALE_THRESHOLD_TICKS = 200

  # --- Public API ---

  def self.create_plan(agent:, goal:, steps:, tick:)
    current = agent.active_plan
    abandon_plan(plan: current, tick: tick, reason: "replaced") if current

    plan = Plan.create!(
      agent: agent,
      goal: goal,
      steps: normalize_steps(steps),
      status: "active",
      created_at_tick: tick,
      last_updated_at_tick: tick
    )

    EventService.append(
      event_type: "plan_created",
      tick: tick,
      agent: agent,
      location: agent.location,
      payload: { plan_id: plan.id, goal: goal, steps: plan.steps }
    )

    plan
  end

  def self.update_plan(plan:, tick:, goal: nil, steps: nil)
    raise PlanError, "Plan is not active" unless plan.status == "active"

    attrs = { last_updated_at_tick: tick }
    attrs[:goal] = goal if goal.present?
    attrs[:steps] = normalize_steps(steps) if steps.present?

    plan.update!(attrs)

    EventService.append(
      event_type: "plan_updated",
      tick: tick,
      agent: plan.agent,
      location: plan.agent.location,
      payload: { plan_id: plan.id, goal: plan.goal, steps: plan.steps }
    )

    plan
  end

  def self.complete_plan(plan:, tick:)
    raise PlanError, "Plan is not active" unless plan.status == "active"

    plan.update!(status: "completed", last_updated_at_tick: tick)

    EventService.append(
      event_type: "plan_completed",
      tick: tick,
      agent: plan.agent,
      location: plan.agent.location,
      payload: { plan_id: plan.id, goal: plan.goal }
    )

    plan
  end

  def self.abandon_plan(plan:, tick:, reason: "abandoned")
    return unless plan.status == "active"

    plan.update!(status: "abandoned", last_updated_at_tick: tick)

    EventService.append(
      event_type: "plan_abandoned",
      tick: tick,
      agent: plan.agent,
      location: plan.agent.location,
      payload: { plan_id: plan.id, goal: plan.goal, reason: reason }
    )

    plan
  end

  # --- Tick listener interface ---

  def self.on_tick(tick)
    abandon_stale_plans(tick)
  end

  def self.name
    "PlanService"
  end

  # --- Private ---

  def self.abandon_stale_plans(tick)
    Plan.active.where("last_updated_at_tick <= ?", tick - STALE_THRESHOLD_TICKS).find_each do |plan|
      abandon_plan(plan: plan, tick: tick, reason: "stale")
    end
  end
  private_class_method :abandon_stale_plans

  def self.normalize_steps(steps)
    return [] unless steps.is_a?(Array)

    steps.map do |step|
      if step.is_a?(String)
        { "description" => step, "done" => false }
      else
        {
          "description" => step["description"] || step[:description] || "",
          "done" => step["done"] || step[:done] || false
        }
      end
    end
  end
  private_class_method :normalize_steps
end
