class Api::V1::BaseController < ActionController::API
  before_action :authenticate_agent!

  rescue_from RateLimitService::RateLimitExceeded do |e|
    response.headers["Retry-After"] = e.retry_after.to_s
    render json: { error: "Rate limit exceeded" }, status: :too_many_requests
  end

  private

  def authenticate_agent!
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")&.strip
    @current_agent = Agent.authenticate(token)

    render_error("Unauthorized", :unauthorized) unless @current_agent
  end

  def current_agent
    @current_agent
  end

  def rate_limit!(category, limit:, window:)
    return unless @current_agent

    RateLimitService.check!("#{@current_agent.id}:#{category}", limit: limit, window: window)
  end

  def render_error(message, status, errors: nil)
    body = { error: message }
    body[:details] = errors if errors.present?
    render json: body, status: status
  end
end
