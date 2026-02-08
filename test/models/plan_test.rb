require "test_helper"

class PlanTest < ActiveSupport::TestCase
  test "valid plan" do
    plan = Plan.new(
      agent: agents(:alice),
      goal: "Explore the town",
      steps: [ { "description" => "Visit Market", "done" => false } ],
      status: "active",
      created_at_tick: 1,
      last_updated_at_tick: 1
    )
    assert plan.valid?
  end

  test "validates goal presence" do
    plan = Plan.new(
      agent: agents(:alice),
      goal: nil,
      status: "active",
      created_at_tick: 1,
      last_updated_at_tick: 1
    )
    assert_not plan.valid?
    assert_includes plan.errors[:goal], "can't be blank"
  end

  test "validates status inclusion" do
    plan = Plan.new(
      agent: agents(:alice),
      goal: "Test",
      status: "invalid",
      created_at_tick: 1,
      last_updated_at_tick: 1
    )
    assert_not plan.valid?
    assert plan.errors[:status].any?
  end

  test "validates created_at_tick presence" do
    plan = Plan.new(
      agent: agents(:alice),
      goal: "Test",
      status: "active",
      created_at_tick: nil,
      last_updated_at_tick: 1
    )
    assert_not plan.valid?
  end

  test "validates last_updated_at_tick presence" do
    plan = Plan.new(
      agent: agents(:alice),
      goal: "Test",
      status: "active",
      created_at_tick: 1,
      last_updated_at_tick: nil
    )
    assert_not plan.valid?
  end

  test "active scope returns only active plans" do
    active_plans = Plan.active
    assert active_plans.all? { |p| p.status == "active" }
  end

  test "for_agent scope filters by agent" do
    alice_plans = Plan.for_agent(agents(:alice))
    assert alice_plans.all? { |p| p.agent_id == agents(:alice).id }
  end

  test "stale? returns true when tick diff >= threshold" do
    plan = plans(:alice_active_plan)
    assert plan.stale?(210)
  end

  test "stale? returns false when tick diff < threshold" do
    plan = plans(:alice_active_plan)
    assert_not plan.stale?(100)
  end

  test "stale? respects custom threshold" do
    plan = plans(:alice_active_plan)
    assert plan.stale?(60, threshold: 50)
    assert_not plan.stale?(60, threshold: 100)
  end

  test "generates prefixed id" do
    plan = Plan.create!(
      agent: agents(:alice),
      goal: "Test plan",
      status: "active",
      created_at_tick: 1,
      last_updated_at_tick: 1
    )
    assert plan.id.start_with?("plan_")
  end
end
