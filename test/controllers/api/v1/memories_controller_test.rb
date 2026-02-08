require "test_helper"

class Api::V1::MemoriesControllerTest < ActionDispatch::IntegrationTest
  test "index returns 401 without authentication" do
    get api_v1_agent_memories_url(agents(:alice).id), as: :json

    assert_response :unauthorized
  end

  test "index returns 403 when requesting another agent's memories" do
    result = Agent.create_with_api_key(
      name: "Snooper",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_memories_url(agents(:alice).id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :forbidden
  end

  test "index returns 404 for unknown agent" do
    result = Agent.create_with_api_key(
      name: "Seeker",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_memories_url("agt_nonexistent000000000000000"),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :not_found
  end

  test "index returns memories for authenticated agent" do
    result = Agent.create_with_api_key(
      name: "Rememberer",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    MemoryService.create_memory(agent: agent, content: "Saw something", importance: 5, tick: 1, location: locations(:town_square))

    get api_v1_agent_memories_url(agent.id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json.key?("memories")
    assert json.key?("meta")
    assert_equal 1, json["memories"].length
    assert_equal "Saw something", json["memories"].first["content"]
  end

  test "index filters by type" do
    result = Agent.create_with_api_key(
      name: "TypeFilter",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    MemoryService.create_memory(agent: agent, content: "obs", importance: 3, tick: 1, type: "observation")
    MemoryService.create_memory(agent: agent, content: "plan", importance: 5, tick: 2, type: "plan")

    get api_v1_agent_memories_url(agent.id),
        params: { type: "observation" },
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json["memories"].all? { |m| m["type"] == "observation" }
    assert_equal 1, json["memories"].length
  end

  test "index filters by min_importance" do
    result = Agent.create_with_api_key(
      name: "ImportFilter",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    MemoryService.create_memory(agent: agent, content: "low", importance: 2, tick: 1)
    MemoryService.create_memory(agent: agent, content: "high", importance: 8, tick: 2)

    get api_v1_agent_memories_url(agent.id),
        params: { min_importance: 5 },
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json["memories"].all? { |m| m["importance"] >= 5 }
    assert_equal 1, json["memories"].length
  end

  test "index respects limit parameter" do
    result = Agent.create_with_api_key(
      name: "LimitTest",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    5.times { |i| MemoryService.create_memory(agent: agent, content: "mem #{i}", importance: 3, tick: i + 1) }

    get api_v1_agent_memories_url(agent.id),
        params: { limit: 2 },
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 2, json["memories"].length
  end

  test "index returns correct memory JSON shape" do
    result = Agent.create_with_api_key(
      name: "ShapeTest",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    MemoryService.create_memory(
      agent: agent,
      content: "Test shape",
      importance: 5,
      tick: 1,
      location: locations(:town_square),
      related_agent_ids: [ agents(:alice).id ]
    )

    get api_v1_agent_memories_url(agent.id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    mem = JSON.parse(response.body)["memories"].first

    assert mem.key?("id")
    assert mem.key?("type")
    assert mem.key?("content")
    assert mem.key?("importance")
    assert mem.key?("tick")
    assert mem.key?("locationId")
    assert mem.key?("relatedAgentIds")
    assert mem.key?("createdAt")
    assert mem["id"].start_with?("mem_")
  end
end
