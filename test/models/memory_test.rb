require "test_helper"

class MemoryTest < ActiveSupport::TestCase
  test "valid memory" do
    mem = Memory.new(
      agent: agents(:alice),
      memory_type: "observation",
      content: "Saw something interesting",
      importance: 5,
      tick: 10,
      location: locations(:town_square)
    )
    assert mem.valid?
  end

  test "validates memory_type inclusion" do
    mem = Memory.new(memory_type: "invalid", content: "test", importance: 5, tick: 1, agent: agents(:alice))
    assert_not mem.valid?
  end

  test "validates importance range" do
    mem = Memory.new(memory_type: "observation", content: "test", importance: 11, tick: 1, agent: agents(:alice))
    assert_not mem.valid?

    mem2 = Memory.new(memory_type: "observation", content: "test", importance: 0, tick: 1, agent: agents(:alice))
    assert_not mem2.valid?
  end

  test "scopes filter by type" do
    assert Memory.observations.all? { |m| m.memory_type == "observation" }
  end

  test "by_importance scope orders correctly" do
    Memory.create!(agent: agents(:alice), memory_type: "observation", content: "High importance", importance: 9, tick: 2)
    Memory.create!(agent: agents(:alice), memory_type: "observation", content: "Low importance", importance: 1, tick: 3)
    mems = Memory.by_importance
    assert mems.count >= 2
    mems.each_cons(2) do |a, b|
      assert a.importance >= b.importance
    end
  end
end
