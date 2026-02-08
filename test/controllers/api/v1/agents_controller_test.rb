require "test_helper"

class Api::V1::AgentsControllerTest < ActionDispatch::IntegrationTest
  # --- POST /api/v1/agents ---

  test "create registers agent and returns agentId and apiKey" do
    assert_difference("Agent.count", 1) do
      post api_v1_agents_url, params: {
        name: "NewAgent",
        description: "A brand new agent",
        personality_traits: [ "brave", "curious" ],
        goals: [ "explore" ]
      }, as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert json["agentId"].start_with?("agt_")
    assert json["apiKey"].start_with?("npc_")
  end

  test "create assigns agent to Town Square" do
    post api_v1_agents_url, params: {
      name: "LocationTest",
      personality_traits: [],
      goals: []
    }, as: :json

    assert_response :created
    agent = Agent.find(JSON.parse(response.body)["agentId"])
    assert_equal locations(:town_square), agent.location
  end

  test "create emits agent_registered event" do
    assert_difference("Event.where(event_type: 'agent_registered').count", 1) do
      post api_v1_agents_url, params: {
        name: "EventTest",
        personality_traits: [],
        goals: []
      }, as: :json
    end
  end

  test "create sets default resources" do
    post api_v1_agents_url, params: {
      name: "DefaultsTest",
      personality_traits: [],
      goals: []
    }, as: :json

    assert_response :created
    agent = Agent.find(JSON.parse(response.body)["agentId"])
    assert_equal 100, agent.stamina
    assert_equal 50, agent.food
    assert_equal 100, agent.energy
    assert_equal 100, agent.currency
  end

  test "create returns 422 when name is missing" do
    post api_v1_agents_url, params: {
      personality_traits: [],
      goals: []
    }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal "Validation failed", json["error"]
  end

  test "create returns 422 when name is taken" do
    post api_v1_agents_url, params: {
      name: agents(:alice).name,
      personality_traits: [],
      goals: []
    }, as: :json

    assert_response :unprocessable_entity
  end

  test "create returns 422 when too many traits" do
    post api_v1_agents_url, params: {
      name: "TooManyTraits",
      personality_traits: %w[a b c d e f],
      goals: []
    }, as: :json

    assert_response :unprocessable_entity
  end

  test "create returns 422 when too many goals" do
    post api_v1_agents_url, params: {
      name: "TooManyGoals",
      personality_traits: [],
      goals: %w[a b c d]
    }, as: :json

    assert_response :unprocessable_entity
  end

  # --- GET /api/v1/agents/:id ---

  test "show returns agent details" do
    get api_v1_agent_url(agents(:alice).id), as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal agents(:alice).id, json["id"]
    assert_equal "Alice", json["name"]
    assert_equal agents(:alice).location_id, json["locationId"]
    assert json.key?("personalityTraits")
    assert json.key?("createdAt")
  end

  test "show returns 404 for unknown agent" do
    get api_v1_agent_url("agt_nonexistent000000000000000"), as: :json

    assert_response :not_found
    json = JSON.parse(response.body)
    assert_equal "Agent not found", json["error"]
  end

  # --- GET /api/v1/agents ---

  test "index returns paginated agents" do
    get api_v1_agents_url, as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json["agents"].is_a?(Array)
    assert json["meta"]["total"] >= 2
    assert_equal 1, json["meta"]["page"]
    assert_equal 20, json["meta"]["perPage"]
  end

  test "index respects page and per_page params" do
    get api_v1_agents_url, params: { page: 1, per_page: 1 }, as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 1, json["agents"].length
    assert_equal 1, json["meta"]["perPage"]
  end

  # --- DELETE /api/v1/agents/:id ---

  test "destroy requires authentication" do
    delete api_v1_agent_url(agents(:alice).id), as: :json

    assert_response :unauthorized
  end

  test "destroy deletes the authenticated agent" do
    result = Agent.create_with_api_key(
      name: "ToDelete",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    assert_difference("Agent.count", -1) do
      delete api_v1_agent_url(result[:agent].id),
             headers: { "Authorization" => "Bearer #{result[:api_key]}" },
             as: :json
    end

    assert_response :no_content
  end

  test "destroy returns 403 when deleting another agent" do
    result = Agent.create_with_api_key(
      name: "Attacker",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    delete api_v1_agent_url(agents(:alice).id),
           headers: { "Authorization" => "Bearer #{result[:api_key]}" },
           as: :json

    assert_response :forbidden
  end

  test "destroy returns 401 with invalid token" do
    delete api_v1_agent_url(agents(:alice).id),
           headers: { "Authorization" => "Bearer npc_invalidtoken000000000000000000000000" },
           as: :json

    assert_response :unauthorized
  end
end
