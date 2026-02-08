require "test_helper"

class Api::V1::ReflectionsControllerTest < ActionDispatch::IntegrationTest
  test "index returns 401 without authentication" do
    get api_v1_agent_reflections_url(agents(:alice).id), as: :json
    assert_response :unauthorized
  end

  test "index returns 403 when requesting another agent's reflections" do
    result = Agent.create_with_api_key(
      name: "Snooper",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_reflections_url(agents(:alice).id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json
    assert_response :forbidden
  end

  test "index returns reflections for authenticated agent" do
    result = Agent.create_with_api_key(
      name: "Reflector",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    MemoryService.create_memory(
      agent: agent, type: "reflection",
      content: "I enjoy the market", importance: 8, tick: 50
    )

    get api_v1_agent_reflections_url(agent.id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json.key?("reflections")
    assert json.key?("meta")
    assert_equal 1, json["reflections"].length
    assert_equal "I enjoy the market", json["reflections"].first["content"]
  end

  test "index only returns reflection-type memories" do
    result = Agent.create_with_api_key(
      name: "TypeCheck",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    MemoryService.create_memory(agent: agent, type: "observation", content: "saw something", importance: 3, tick: 1)
    MemoryService.create_memory(agent: agent, type: "reflection", content: "I think about stuff", importance: 8, tick: 50)

    get api_v1_agent_reflections_url(agent.id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 1, json["reflections"].length
    assert_equal "I think about stuff", json["reflections"].first["content"]
  end
end
