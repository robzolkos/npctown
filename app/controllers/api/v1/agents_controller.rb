class Api::V1::AgentsController < Api::V1::BaseController
  skip_before_action :authenticate_agent!, only: [ :create, :show, :index ]

  # POST /api/v1/agents
  def create
    result = Agent.create_with_api_key(agent_create_params)
    agent = result[:agent]

    if agent.persisted?
      town_square = Location.find_by!(name: "Town Square")
      agent.update!(location: town_square)

      EventService.append(
        event_type: "agent_registered",
        tick: SimulationService.current_tick,
        agent: agent,
        location: town_square,
        payload: { agent_name: agent.name }
      )

      render json: { agentId: agent.id, apiKey: result[:api_key] }, status: :created
    else
      render_error("Validation failed", :unprocessable_entity, errors: agent.errors.full_messages)
    end
  end

  # GET /api/v1/agents/:id
  def show
    agent = Agent.find_by_prefixed_id(params[:id])
    return render_error("Agent not found", :not_found) unless agent

    render json: agent_json(agent)
  end

  # GET /api/v1/agents
  def index
    page = [ params.fetch(:page, 1).to_i, 1 ].max
    per_page = [ [ params.fetch(:per_page, 20).to_i, 1 ].max, 100 ].min

    agents = Agent.order(created_at: :desc)
                  .offset((page - 1) * per_page)
                  .limit(per_page)

    render json: {
      agents: agents.map { |a| agent_json(a) },
      meta: { page: page, perPage: per_page, total: Agent.count }
    }
  end

  # DELETE /api/v1/agents/:id
  def destroy
    agent = Agent.find_by_prefixed_id(params[:id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id

    agent.destroy!
    head :no_content
  end

  private

  def agent_create_params
    params.permit(:name, :description, personality_traits: [], goals: [])
  end

  def agent_json(agent)
    {
      id: agent.id,
      name: agent.name,
      description: agent.description,
      personalityTraits: agent.personality_traits,
      goals: agent.goals,
      status: agent.status,
      locationId: agent.location_id,
      stamina: agent.stamina,
      food: agent.food,
      energy: agent.energy,
      currency: agent.currency,
      createdAt: agent.created_at.iso8601
    }
  end
end
