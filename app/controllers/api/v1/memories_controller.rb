class Api::V1::MemoriesController < Api::V1::BaseController
  def index
    agent = Agent.find_by_prefixed_id(params[:agent_id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id

    memories = MemoryService.memories_for(
      agent: agent,
      type: params[:type],
      min_importance: params[:min_importance]&.to_i,
      since_tick: params[:since_tick]&.to_i,
      limit: [ params.fetch(:limit, 50).to_i, 100 ].min
    )

    render json: {
      memories: memories.map { |m| memory_json(m) },
      meta: { count: memories.size }
    }
  end

  private

  def memory_json(memory)
    {
      id: memory.id,
      type: memory.memory_type,
      content: memory.content,
      importance: memory.importance,
      tick: memory.tick,
      locationId: memory.location_id,
      relatedAgentIds: memory.related_agent_ids,
      createdAt: memory.created_at.iso8601
    }
  end
end
