require "test_helper"

class Api::V1::ActionsControllerTest < ActionDispatch::IntegrationTest
  test "create returns 401 without authentication" do
    post api_v1_agent_actions_url(agents(:alice).id),
         params: { type: "wait" },
         as: :json

    assert_response :unauthorized
  end

  test "create returns 403 when acting as another agent" do
    result = Agent.create_with_api_key(
      name: "Intruder",
      personality_traits: [],
      goals: [],
      location: locations(:town_square),
      status: "active"
    )

    post api_v1_agent_actions_url(agents(:alice).id),
         params: { type: "wait" },
         headers: { "Authorization" => "Bearer #{result[:api_key]}" },
         as: :json

    assert_response :forbidden
  end

  test "create returns 404 for unknown agent" do
    result = Agent.create_with_api_key(
      name: "Searcher",
      personality_traits: [],
      goals: [],
      location: locations(:town_square),
      status: "active"
    )

    post api_v1_agent_actions_url("agt_nonexistent000000000000000"),
         params: { type: "wait" },
         headers: { "Authorization" => "Bearer #{result[:api_key]}" },
         as: :json

    assert_response :not_found
  end

  test "create wait action succeeds" do
    result = Agent.create_with_api_key(
      name: "Waiter",
      personality_traits: [],
      goals: [],
      location: locations(:town_square),
      status: "active"
    )

    post api_v1_agent_actions_url(result[:agent].id),
         params: { type: "wait" },
         headers: { "Authorization" => "Bearer #{result[:api_key]}" },
         as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert json["success"]
    assert json.key?("tick")
  end

  test "create move action succeeds" do
    result = Agent.create_with_api_key(
      name: "Mover",
      personality_traits: [],
      goals: [],
      location: locations(:town_square),
      status: "active"
    )

    post api_v1_agent_actions_url(result[:agent].id),
         params: { type: "move", targetLocationId: locations(:market).id },
         headers: { "Authorization" => "Bearer #{result[:api_key]}" },
         as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert json["success"]
    assert_not_nil json["event"]
  end

  test "create speak action succeeds" do
    result = Agent.create_with_api_key(
      name: "Speaker",
      personality_traits: [],
      goals: [],
      location: locations(:town_square),
      status: "active"
    )

    post api_v1_agent_actions_url(result[:agent].id),
         params: { type: "speak", message: "Hello everyone!" },
         headers: { "Authorization" => "Bearer #{result[:api_key]}" },
         as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert json["success"]
    assert_equal "Hello everyone!", json["event"]["payload"]["message"]
  end

  test "create returns 422 for invalid action type" do
    result = Agent.create_with_api_key(
      name: "BadActor",
      personality_traits: [],
      goals: [],
      location: locations(:town_square),
      status: "active"
    )

    post api_v1_agent_actions_url(result[:agent].id),
         params: { type: "fly" },
         headers: { "Authorization" => "Bearer #{result[:api_key]}" },
         as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert json["error"].present?
  end

  test "create returns 429 when rate limited" do
    result = Agent.create_with_api_key(
      name: "RateLimitedActor",
      personality_traits: [],
      goals: [],
      location: locations(:town_square),
      status: "active"
    )
    headers = { "Authorization" => "Bearer #{result[:api_key]}" }

    post api_v1_agent_actions_url(result[:agent].id),
         params: { type: "wait" }, headers: headers, as: :json
    assert_response :created

    post api_v1_agent_actions_url(result[:agent].id),
         params: { type: "wait" }, headers: headers, as: :json
    assert_response :too_many_requests

    json = JSON.parse(response.body)
    assert_equal "Rate limit exceeded", json["error"]
    assert response.headers["Retry-After"].present?
  end

  test "create returns 422 when stamina insufficient" do
    result = Agent.create_with_api_key(
      name: "Exhausted",
      personality_traits: [],
      goals: [],
      location: locations(:town_square),
      status: "active"
    )
    result[:agent].update!(stamina: 0)

    post api_v1_agent_actions_url(result[:agent].id),
         params: { type: "speak", message: "I'm tired" },
         headers: { "Authorization" => "Bearer #{result[:api_key]}" },
         as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
  end
end
