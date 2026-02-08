class Api::V1::ActionsController < Api::V1::BaseController
  # POST /api/v1/agents/:agent_id/actions
  def create
    agent = Agent.find_by_prefixed_id(params[:agent_id])
    return render_error("Agent not found", :not_found) unless agent
    return render_error("Forbidden", :forbidden) unless agent.id == current_agent.id

    result = ActionService.execute(
      agent: agent,
      action_type: params[:type],
      params: action_params
    )

    render json: result, status: :created
  rescue ActionService::ActionError, WorldService::MovementError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def action_params
    {
      target_location_id: params[:targetLocationId],
      message: params[:message],
      description: params[:description]
    }
  end
end
