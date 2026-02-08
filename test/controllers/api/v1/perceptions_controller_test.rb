require "test_helper"

class Api::V1::PerceptionsControllerTest < ActionDispatch::IntegrationTest
  test "show returns 401 without authentication" do
    get api_v1_agent_perception_url(agents(:alice).id), as: :json

    assert_response :unauthorized
  end

  test "show returns 403 when requesting another agent's perception" do
    result = Agent.create_with_api_key(
      name: "OtherAgent",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_perception_url(agents(:alice).id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :forbidden
  end

  test "show returns 404 for unknown agent" do
    result = Agent.create_with_api_key(
      name: "Searcher",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_perception_url("agt_nonexistent000000000000000"),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :not_found
  end

  test "show returns perception for authenticated agent" do
    result = Agent.create_with_api_key(
      name: "Perceiver",
      personality_traits: [ "curious" ],
      goals: [ "explore" ],
      location: locations(:town_square)
    )

    get api_v1_agent_perception_url(result[:agent].id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)

    assert json.key?("tick")
    assert json.key?("location")
    assert json.key?("nearbyAgents")
    assert json.key?("activeConversations")
    assert json.key?("recentEvents")
    assert json.key?("recentMemories")
    assert json.key?("self")
    assert json.key?("availableActions")
    assert json.key?("allLocations")
  end

  test "show returns correct location data" do
    result = Agent.create_with_api_key(
      name: "LocationCheck",
      personality_traits: [],
      goals: [],
      location: locations(:market)
    )

    get api_v1_agent_perception_url(result[:agent].id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal "Market", json["location"]["name"]
  end

  test "show returns self with correct resource values" do
    result = Agent.create_with_api_key(
      name: "ResourceCheck",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_perception_url(result[:agent].id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    self_data = json["self"]
    assert_equal result[:agent].id, self_data["id"]
    assert_equal 100, self_data["stamina"]
    assert_equal 50, self_data["food"]
    assert_equal 100, self_data["energy"]
    assert_equal 100, self_data["currency"]
  end

  test "show returns 429 when rate limited" do
    result = Agent.create_with_api_key(
      name: "RateLimited",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    headers = { "Authorization" => "Bearer #{result[:api_key]}" }

    get api_v1_agent_perception_url(result[:agent].id), headers: headers, as: :json
    assert_response :ok

    get api_v1_agent_perception_url(result[:agent].id), headers: headers, as: :json
    assert_response :too_many_requests

    json = JSON.parse(response.body)
    assert_equal "Rate limit exceeded", json["error"]
    assert response.headers["Retry-After"].present?
  end

  test "show returns allLocations with agent counts" do
    result = Agent.create_with_api_key(
      name: "CountCheck",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_perception_url(result[:agent].id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal Location.count, json["allLocations"].length
    json["allLocations"].each do |loc|
      assert loc.key?("agentCount")
      assert loc.key?("name")
    end
  end
end
