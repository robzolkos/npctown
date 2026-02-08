require "test_helper"

class Api::V1::PlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @result = Agent.create_with_api_key(
      name: "Planner",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    @agent = @result[:agent]
    @agent.update!(status: "active")
    @api_key = @result[:api_key]
    @auth_headers = { "Authorization" => "Bearer #{@api_key}" }
  end

  # --- GET show ---

  test "show returns 401 without authentication" do
    get api_v1_agent_plan_url(@agent.id), as: :json
    assert_response :unauthorized
  end

  test "show returns 403 for another agent's plan" do
    other_result = Agent.create_with_api_key(
      name: "Other",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_plan_url(@agent.id),
        headers: { "Authorization" => "Bearer #{other_result[:api_key]}" },
        as: :json
    assert_response :forbidden
  end

  test "show returns 404 when no active plan" do
    get api_v1_agent_plan_url(@agent.id),
        headers: @auth_headers,
        as: :json
    assert_response :not_found
  end

  test "show returns active plan" do
    PlanService.create_plan(
      agent: @agent,
      goal: "Explore the town",
      steps: [ "Visit Market" ],
      tick: 10
    )

    get api_v1_agent_plan_url(@agent.id),
        headers: @auth_headers,
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json.key?("plan")
    assert_equal "Explore the town", json["plan"]["goal"]
    assert_equal "active", json["plan"]["status"]
    assert_equal 1, json["plan"]["steps"].size
  end

  # --- POST create ---

  test "create returns 401 without authentication" do
    post api_v1_agent_plan_url(@agent.id),
         params: { goal: "Test" },
         as: :json
    assert_response :unauthorized
  end

  test "create returns 422 without goal" do
    post api_v1_agent_plan_url(@agent.id),
         params: {},
         headers: @auth_headers,
         as: :json
    assert_response :unprocessable_entity
  end

  test "create creates a new plan" do
    assert_difference "Plan.count" do
      post api_v1_agent_plan_url(@agent.id),
           params: { goal: "Make friends", steps: [ "Say hello", "Start a conversation" ] },
           headers: @auth_headers,
           as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "Make friends", json["plan"]["goal"]
    assert_equal 2, json["plan"]["steps"].size
    assert json["plan"]["id"].start_with?("plan_")
  end

  test "create replaces existing active plan" do
    PlanService.create_plan(agent: @agent, goal: "Old plan", steps: [], tick: 5)

    post api_v1_agent_plan_url(@agent.id),
         params: { goal: "New plan" },
         headers: @auth_headers,
         as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "New plan", json["plan"]["goal"]

    assert_equal 1, @agent.plans.active.count
    assert_equal 1, @agent.plans.where(status: "abandoned").count
  end

  # --- PATCH update ---

  test "update returns 404 when no active plan" do
    patch api_v1_agent_plan_url(@agent.id),
          params: { goal: "Updated" },
          headers: @auth_headers,
          as: :json
    assert_response :not_found
  end

  test "update modifies plan goal and steps" do
    PlanService.create_plan(agent: @agent, goal: "Original", steps: [], tick: 10)

    patch api_v1_agent_plan_url(@agent.id),
          params: { goal: "Updated goal", steps: [ "New step" ] },
          headers: @auth_headers,
          as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "Updated goal", json["plan"]["goal"]
    assert_equal 1, json["plan"]["steps"].size
  end

  test "update with action_type complete completes the plan" do
    PlanService.create_plan(agent: @agent, goal: "Finish this", steps: [], tick: 10)

    patch api_v1_agent_plan_url(@agent.id),
          params: { action_type: "complete" },
          headers: @auth_headers,
          as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "completed", json["plan"]["status"]
  end

  test "update with action_type abandon abandons the plan" do
    PlanService.create_plan(agent: @agent, goal: "Give up", steps: [], tick: 10)

    patch api_v1_agent_plan_url(@agent.id),
          params: { action_type: "abandon" },
          headers: @auth_headers,
          as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "abandoned", json["plan"]["status"]
  end
end
