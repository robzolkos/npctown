class Api::V1::Gate::ApplicationsController < Api::V1::BaseController
  skip_before_action :authenticate_agent!
  before_action :authenticate_owner!
  wrap_parameters false

  rescue_from ActiveRecord::RecordNotFound do
    render_error("Not found", :not_found)
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render_error(e.record.errors.full_messages.join(", "), :unprocessable_entity)
  end

  # POST /api/v1/gate/applications
  def create
    result = GateInterviewService.apply(
      owner: current_owner,
      agent_params: application_params
    )

    render json: {
      applicationId: result[:application].id,
      status: result[:application].status,
      question: result[:question],
      questionNumber: result[:question_number],
      totalQuestions: result[:total_questions]
    }, status: :created
  rescue GateInterviewService::InterviewError => e
    render_error(e.message, :unprocessable_entity)
  end

  # GET /api/v1/gate/applications/:id
  def show
    application = current_owner.gate_applications.find(params[:id])

    response_data = {
      applicationId: application.id,
      status: application.status,
      agentName: application.agent_name,
      questionNumber: application.current_question_index,
      totalQuestions: GateApplication::QUESTIONS_PER_INTERVIEW
    }

    if application.status == "passed"
      api_key = fetch_cached_api_key(application.id)
      response_data[:agentApiKey] = api_key if api_key.present?
    end

    render json: response_data
  end

  # POST /api/v1/gate/applications/:id/respond
  def respond
    application = current_owner.gate_applications.find(params[:id])

    result = GateInterviewService.respond(
      application: application,
      answer: params[:answer]
    )

    if result[:status] == "judging"
      render json: { status: result[:status], message: result[:message] }
    else
      render json: {
        status: result[:status],
        question: result[:question],
        questionNumber: result[:question_number],
        totalQuestions: result[:total_questions]
      }
    end
  rescue GateInterviewService::InterviewError => e
    render_error(e.message, :unprocessable_entity)
  end

  private

  def application_params
    params.permit(:name, :description, personality_traits: [], goals: [])
  end

  def fetch_cached_api_key(application_id)
    Sidekiq.redis { |conn| conn.get("gate:api_key:#{application_id}") }
  rescue StandardError
    nil
  end
end
