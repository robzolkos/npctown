class Api::V1::RelationshipsController < Api::V1::BaseController
  before_action :enforce_rate_limit

  def index
    agent = Agent.find_by_prefixed_id(params[:agent_id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id

    relationships = agent.relationships.includes(:target_agent)

    render json: {
      relationships: relationships.map { |r| relationship_json(r) },
      meta: { count: relationships.size }
    }
  end

  private

  def enforce_rate_limit
    rate_limit!("data", limit: 10, window: 60)
  end

  def relationship_json(rel)
    {
      targetAgentId: rel.target_agent_id,
      targetAgentName: rel.target_agent.name,
      trust: rel.trust,
      affection: rel.affection,
      respect: rel.respect,
      familiarity: rel.familiarity,
      label: rel.label,
      lastInteractionTick: rel.last_interaction_tick
    }
  end
end
