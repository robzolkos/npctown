class Api::V1::PerceptionsController < Api::V1::BaseController
  # GET /api/v1/agents/:agent_id/perception
  def show
    agent = Agent.find_by_prefixed_id(params[:agent_id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id

    render json: PerceptionService.build(agent)
  end
end
