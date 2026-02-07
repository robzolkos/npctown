require "test_helper"

class AgentTest < ActiveSupport::TestCase
  test "create_with_api_key returns agent and key" do
    result = Agent.create_with_api_key(
      name: "TestAgent",
      description: "A test agent",
      personality_traits: [ "brave" ],
      goals: [ "survive" ],
      location: locations(:town_square)
    )

    assert result[:agent].persisted?
    assert result[:api_key].start_with?("npc_")
    assert_equal 44, result[:api_key].length
  end

  test "authenticate finds agent by raw key" do
    result = Agent.create_with_api_key(
      name: "AuthTest",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )

    found = Agent.authenticate(result[:api_key])
    assert_equal result[:agent], found
  end

  test "authenticate returns nil for invalid key" do
    assert_nil Agent.authenticate("npc_invalidkey12345678901234567890123456789")
    assert_nil Agent.authenticate(nil)
    assert_nil Agent.authenticate("")
    assert_nil Agent.authenticate("wrong_prefix")
  end

  test "validates personality_traits max 5" do
    result = Agent.create_with_api_key(
      name: "TooManyTraits",
      personality_traits: %w[a b c d e f],
      goals: []
    )
    assert_not result[:agent].persisted?
    assert_includes result[:agent].errors[:personality_traits], "cannot have more than 5 traits"
  end

  test "validates goals max 3" do
    result = Agent.create_with_api_key(
      name: "TooManyGoals",
      personality_traits: [],
      goals: %w[a b c d]
    )
    assert_not result[:agent].persisted?
    assert_includes result[:agent].errors[:goals], "cannot have more than 3 goals"
  end

  test "status must be valid" do
    agent = agents(:alice)
    agent.status = "invalid"
    assert_not agent.valid?
  end

  test "scopes filter correctly" do
    assert Agent.active.all? { |a| a.status == "active" }
    assert Agent.at_location(locations(:town_square)).all? { |a| a.location == locations(:town_square) }
  end

  test "generated ID has agt prefix" do
    result = Agent.create_with_api_key(
      name: "PrefixTest",
      personality_traits: [],
      goals: [],
      location: locations(:town_square)
    )
    assert result[:agent].id.start_with?("agt_")
  end
end
