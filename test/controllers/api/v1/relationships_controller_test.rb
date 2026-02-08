require "test_helper"

class Api::V1::RelationshipsControllerTest < ActionDispatch::IntegrationTest
  test "index returns 401 without authentication" do
    get api_v1_agent_relationships_url(agents(:alice).id), as: :json

    assert_response :unauthorized
  end

  test "index returns 403 when requesting another agent's relationships" do
    result = Agent.create_with_api_key(
      name: "Snooper",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    get api_v1_agent_relationships_url(agents(:alice).id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :forbidden
  end

  test "index returns relationships for authenticated agent" do
    result = Agent.create_with_api_key(
      name: "Social",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    # Create a relationship for this agent
    target = agents(:alice)
    Relationship.create!(agent: agent, target_agent: target, trust: 10, familiarity: 30)

    get api_v1_agent_relationships_url(agent.id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    json = JSON.parse(response.body)
    assert json.key?("relationships")
    assert json.key?("meta")
    assert_equal 1, json["relationships"].length
  end

  test "index returns correct JSON shape" do
    result = Agent.create_with_api_key(
      name: "ShapeCheck",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    agent = result[:agent]

    target = agents(:bob)
    Relationship.create!(agent: agent, target_agent: target, trust: 20, affection: 15, respect: 25, familiarity: 40, last_interaction_tick: 10)

    get api_v1_agent_relationships_url(agent.id),
        headers: { "Authorization" => "Bearer #{result[:api_key]}" },
        as: :json

    assert_response :ok
    rel = JSON.parse(response.body)["relationships"].first

    assert rel.key?("targetAgentId")
    assert rel.key?("targetAgentName")
    assert rel.key?("trust")
    assert rel.key?("affection")
    assert rel.key?("respect")
    assert rel.key?("familiarity")
    assert rel.key?("label")
    assert rel.key?("lastInteractionTick")
    assert_equal "Bob", rel["targetAgentName"]
  end
end
