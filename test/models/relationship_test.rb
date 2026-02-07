require "test_helper"

class RelationshipTest < ActiveSupport::TestCase
  test "label returns stranger for low familiarity" do
    rel = Relationship.new(familiarity: 5, trust: 0, affection: 0, respect: 0)
    assert_equal "Stranger", rel.label
  end

  test "label returns acquaintance for moderate familiarity" do
    rel = Relationship.new(familiarity: 20, trust: 0, affection: 0, respect: 0)
    assert_equal "Acquaintance", rel.label
  end

  test "label returns close friend for high trust and affection" do
    rel = Relationship.new(familiarity: 50, trust: 50, affection: 50, respect: 50)
    assert_equal "Close Friend", rel.label
  end

  test "label returns nemesis for all very negative" do
    rel = Relationship.new(familiarity: 50, trust: -60, affection: -60, respect: -60)
    assert_equal "Nemesis", rel.label
  end

  test "cannot reference self" do
    rel = Relationship.new(
      agent: agents(:alice),
      target_agent: agents(:alice),
      trust: 0, affection: 0, respect: 0, familiarity: 0
    )
    assert_not rel.valid?
    assert_includes rel.errors[:target_agent], "cannot be the same as agent"
  end

  test "validates dimension ranges" do
    rel = relationships(:alice_knows_bob)
    rel.trust = 101
    assert_not rel.valid?

    rel.trust = 50
    rel.familiarity = -1
    assert_not rel.valid?
  end

  test "fixture relationship has correct label" do
    rel = relationships(:alice_knows_bob)
    assert_equal "Acquaintance", rel.label
  end
end
