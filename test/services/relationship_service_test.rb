require "test_helper"

class RelationshipServiceTest < ActiveSupport::TestCase
  test "find_or_create creates a new relationship with defaults" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    # Ensure no existing relationship
    Relationship.where(agent: alice, target_agent: charlie).delete_all

    rel = RelationshipService.find_or_create(agent: alice, target_agent: charlie)

    assert_equal alice.id, rel.agent_id
    assert_equal charlie.id, rel.target_agent_id
    assert_equal 0, rel.trust
    assert_equal 0, rel.affection
    assert_equal 0, rel.respect
    assert_equal 0, rel.familiarity
  end

  test "find_or_create returns existing relationship" do
    alice = agents(:alice)
    bob = agents(:bob)

    rel = RelationshipService.find_or_create(agent: alice, target_agent: bob)

    assert_equal relationships(:alice_knows_bob).id, rel.id
    assert_equal 20, rel.trust
  end

  test "on_conversation_started updates both directions" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    # Clear any existing relationships
    Relationship.where(agent: alice, target_agent: charlie).delete_all
    Relationship.where(agent: charlie, target_agent: alice).delete_all

    RelationshipService.on_conversation_started(initiator: alice, target_agent: charlie, tick: 10)

    a_to_c = Relationship.find_by(agent: alice, target_agent: charlie)
    c_to_a = Relationship.find_by(agent: charlie, target_agent: alice)

    assert_not_nil a_to_c
    assert_not_nil c_to_a
    assert_equal 3, a_to_c.familiarity
    assert_equal 1, a_to_c.trust
    assert_equal 3, c_to_a.familiarity
    assert_equal 1, c_to_a.trust
  end

  test "on_conversation_message updates speaker with all participants" do
    alice = agents(:alice)
    bob = agents(:bob)

    original_trust = relationships(:alice_knows_bob).trust
    original_familiarity = relationships(:alice_knows_bob).familiarity

    RelationshipService.on_conversation_message(speaker: alice, other_participants: [ bob ], tick: 15)

    rel = relationships(:alice_knows_bob).reload
    assert_equal original_trust + 1, rel.trust
    assert_equal original_familiarity + 1, rel.familiarity
    assert_equal 15, rel.last_interaction_tick
  end

  test "dimensions clamp to valid ranges" do
    alice = agents(:alice)
    bob = agents(:bob)

    # Set trust near max
    relationships(:alice_knows_bob).update!(trust: 99)

    RelationshipService.on_conversation_started(initiator: alice, target_agent: bob, tick: 20)

    rel = relationships(:alice_knows_bob).reload
    assert_equal 100, rel.trust
  end

  test "familiarity clamps to 0-100 range" do
    alice = agents(:alice)
    bob = agents(:bob)

    relationships(:alice_knows_bob).update!(familiarity: 99)

    RelationshipService.on_conversation_started(initiator: alice, target_agent: bob, tick: 20)

    rel = relationships(:alice_knows_bob).reload
    assert_equal 100, rel.familiarity
  end

  test "emits relationship_changed event" do
    alice = agents(:alice)
    charlie = agents(:charlie)
    Relationship.where(agent: alice, target_agent: charlie).delete_all
    Relationship.where(agent: charlie, target_agent: alice).delete_all

    assert_difference -> { Event.where(event_type: "relationship_changed").count }, 2 do
      RelationshipService.on_conversation_started(initiator: alice, target_agent: charlie, tick: 10)
    end

    event = Event.where(event_type: "relationship_changed", agent: alice).last
    assert_equal charlie.id, event.payload["target_agent_id"]
    assert_equal "Charlie", event.payload["target_agent_name"]
    assert event.payload.key?("trust")
    assert event.payload.key?("familiarity")
    assert event.payload.key?("label")
  end

  test "last_interaction_tick updates on each interaction" do
    alice = agents(:alice)
    bob = agents(:bob)

    RelationshipService.on_conversation_message(speaker: alice, other_participants: [ bob ], tick: 42)

    assert_equal 42, relationships(:alice_knows_bob).reload.last_interaction_tick
  end

  test "relationships_for returns non-stranger relationships" do
    alice = agents(:alice)

    results = RelationshipService.relationships_for(agent: alice)

    # alice_knows_bob has familiarity 40, should be included
    assert results.any? { |r| r.target_agent_id == agents(:bob).id }
  end

  test "relationships_for excludes strangers" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    # Create a low-familiarity relationship
    Relationship.where(agent: alice, target_agent: charlie).delete_all
    Relationship.create!(agent: alice, target_agent: charlie, familiarity: 5)

    results = RelationshipService.relationships_for(agent: alice)
    assert_not results.any? { |r| r.target_agent_id == charlie.id }
  end
end
