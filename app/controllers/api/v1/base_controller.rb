class Api::V1::BaseController < ActionController::API
  before_action :authenticate_agent!

  private

  def authenticate_agent!
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip
    @current_agent = Agent.authenticate(token)

    render_error("Unauthorized", :unauthorized) unless @current_agent
  end

  def current_agent
    @current_agent
  end

  def render_error(message, status, errors: nil)
    body = { error: message }
    body[:details] = errors if errors.present?
    render json: body, status: status
  end
end
