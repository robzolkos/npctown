require "test_helper"

class Api::V1::Gate::ApplicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    result = Owner.create_with_api_key(
      email: "gate_test@example.com",
      password: "password123",
      password_confirmation: "password123",
      verified_at: 1.day.ago
    )
    @owner = result[:owner]
    @api_key = result[:api_key]
    @auth_headers = { "Authorization" => "Bearer #{@api_key}" }

    # Clear active fixture applications for this owner
    @owner.gate_applications.active.destroy_all
  end

  # --- POST /api/v1/gate/applications (create) ---

  test "create starts interview and returns first question" do
    assert_difference("GateApplication.count", 1) do
      post api_v1_gate_applications_url,
        params: { name: "TestBot", description: "A test bot", personality_traits: [ "curious" ], goals: [ "explore" ] },
        headers: @auth_headers,
        as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert json["applicationId"].start_with?("gapp_")
    assert_equal "interviewing", json["status"]
    assert json["question"].present?
    assert_equal 1, json["questionNumber"]
    assert_equal 5, json["totalQuestions"]
  end

  test "create returns 401 without authentication" do
    post api_v1_gate_applications_url, params: { name: "Bot" }, as: :json

    assert_response :unauthorized
  end

  test "create returns 422 with missing name" do
    post api_v1_gate_applications_url,
      params: { description: "No name" },
      headers: @auth_headers,
      as: :json

    assert_response :unprocessable_entity
  end

  test "create returns 422 when owner already has active application" do
    post api_v1_gate_applications_url,
      params: { name: "FirstBot" },
      headers: @auth_headers,
      as: :json
    assert_response :created

    post api_v1_gate_applications_url,
      params: { name: "SecondBot" },
      headers: @auth_headers,
      as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/active application/i, json["error"])
  end

  test "create returns 422 when agent name is taken" do
    post api_v1_gate_applications_url,
      params: { name: agents(:alice).name },
      headers: @auth_headers,
      as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/already taken/i, json["error"])
  end

  # --- GET /api/v1/gate/applications/:id (show) ---

  test "show returns application status" do
    application = @owner.gate_applications.create!(
      status: "interviewing",
      agent_name: "StatusBot",
      questions: [ { id: "q1", text: "Question?" } ],
      current_question_index: 0,
      expires_at: 10.minutes.from_now
    )

    get api_v1_gate_application_url(application),
      headers: @auth_headers,
      as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal application.id, json["applicationId"]
    assert_equal "interviewing", json["status"]
    assert_equal "StatusBot", json["agentName"]
  end

  test "show returns 404 for another owner's application" do
    other_result = Owner.create_with_api_key(
      email: "other_gate@example.com",
      password: "password123",
      password_confirmation: "password123",
      verified_at: 1.day.ago
    )
    other_app = other_result[:owner].gate_applications.create!(
      status: "interviewing",
      agent_name: "OtherBot",
      questions: [ { id: "q1", text: "Q?" } ],
      current_question_index: 0,
      expires_at: 10.minutes.from_now
    )

    get api_v1_gate_application_url(other_app),
      headers: @auth_headers,
      as: :json

    assert_response :not_found
  end

  test "show returns 404 for nonexistent application" do
    get api_v1_gate_application_url("gapp_nonexistent"),
      headers: @auth_headers,
      as: :json

    assert_response :not_found
  end

  test "show includes agentApiKey for passed application" do
    application = @owner.gate_applications.create!(
      status: "passed",
      agent_name: "PassedBot",
      questions: [],
      current_question_index: 5
    )

    test_api_key = "npc_test_key_123"
    Sidekiq.redis { |conn| conn.set("gate:api_key:#{application.id}", test_api_key, ex: 3600) }

    get api_v1_gate_application_url(application),
      headers: @auth_headers,
      as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal test_api_key, json["agentApiKey"]
  end

  # --- POST /api/v1/gate/applications/:id/respond ---

  test "respond submits answer and returns next question" do
    application = @owner.gate_applications.create!(
      status: "interviewing",
      agent_name: "RespondBot",
      questions: [
        { id: "q1", category: "intent", text: "Question 1?" },
        { id: "q2", category: "identity", text: "Question 2?" }
      ],
      current_question_index: 0,
      responses: [],
      expires_at: 10.minutes.from_now
    )

    post respond_api_v1_gate_application_url(application),
      params: { answer: "My answer to question 1" },
      headers: @auth_headers,
      as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "interviewing", json["status"]
    assert_equal "Question 2?", json["question"]
    assert_equal 2, json["questionNumber"]
  end

  test "respond with final answer transitions to judging" do
    application = @owner.gate_applications.create!(
      status: "interviewing",
      agent_name: "FinalBot",
      questions: [ { id: "q1", category: "intent", text: "Final question?" } ],
      current_question_index: 0,
      responses: [],
      expires_at: 10.minutes.from_now
    )

    post respond_api_v1_gate_application_url(application),
      params: { answer: "Final answer" },
      headers: @auth_headers,
      as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "judging", json["status"]
    assert json["message"].present?
  end

  test "respond returns 422 when application expired" do
    application = @owner.gate_applications.create!(
      status: "interviewing",
      agent_name: "ExpiredBot",
      questions: [ { id: "q1", category: "intent", text: "Question?" } ],
      current_question_index: 0,
      responses: [],
      expires_at: 1.minute.ago
    )

    post respond_api_v1_gate_application_url(application),
      params: { answer: "Too late" },
      headers: @auth_headers,
      as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/expired/i, json["error"])
  end

  test "respond returns 422 when not in interviewing status" do
    application = @owner.gate_applications.create!(
      status: "judging",
      agent_name: "JudgingBot",
      questions: [],
      current_question_index: 5
    )

    post respond_api_v1_gate_application_url(application),
      params: { answer: "Answer" },
      headers: @auth_headers,
      as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_match(/not in interviewing status/i, json["error"])
  end
end
