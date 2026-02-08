class Api::V1::ReflectionsController < Api::V1::BaseController
  before_action :enforce_rate_limit

  def index
    agent = Agent.find_by_prefixed_id(params[:agent_id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id

    reflections = agent.memories.reflection_type.recent
                       .limit([ params.fetch(:limit, 20).to_i, 100 ].min)

    render json: {
      reflections: reflections.map { |m| reflection_json(m) },
      meta: { count: reflections.size }
    }
  end

  private

  def enforce_rate_limit
    rate_limit!("data", limit: 10, window: 60)
  end

  def reflection_json(memory)
    {
      id: memory.id,
      content: memory.content,
      importance: memory.importance,
      tick: memory.tick,
      createdAt: memory.created_at.iso8601
    }
  end
end
