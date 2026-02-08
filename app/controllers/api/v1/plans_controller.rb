class Api::V1::PlansController < Api::V1::BaseController
  # GET /api/v1/agents/:agent_id/plan
  def show
    agent = Agent.find_by_prefixed_id(params[:agent_id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id

    plan = agent.active_plan
    return render_error("No active plan", :not_found) unless plan

    render json: { plan: plan_json(plan) }
  end

  # POST /api/v1/agents/:agent_id/plan
  def create
    agent = Agent.find_by_prefixed_id(params[:agent_id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id
    return render_error("goal is required", :unprocessable_entity) unless params[:goal].present?

    tick = SimulationService.current_tick

    plan = PlanService.create_plan(
      agent: agent,
      goal: params[:goal],
      steps: params[:steps] || [],
      tick: tick
    )

    render json: { plan: plan_json(plan) }, status: :created
  end

  # PATCH /api/v1/agents/:agent_id/plan
  def update
    agent = Agent.find_by_prefixed_id(params[:agent_id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id

    plan = agent.active_plan
    return render_error("No active plan", :not_found) unless plan

    tick = SimulationService.current_tick

    case params[:action_type]
    when "complete"
      PlanService.complete_plan(plan: plan, tick: tick)
    when "abandon"
      PlanService.abandon_plan(plan: plan, tick: tick)
    else
      PlanService.update_plan(
        plan: plan,
        tick: tick,
        goal: params[:goal],
        steps: params[:steps]
      )
    end

    render json: { plan: plan_json(plan.reload) }
  rescue PlanService::PlanError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def plan_json(plan)
    {
      id: plan.id,
      goal: plan.goal,
      steps: plan.steps,
      status: plan.status,
      createdAtTick: plan.created_at_tick,
      lastUpdatedAtTick: plan.last_updated_at_tick,
      createdAt: plan.created_at.iso8601
    }
  end
end
