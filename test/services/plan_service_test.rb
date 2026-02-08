require "test_helper"

class PlanServiceTest < ActiveSupport::TestCase
  setup do
    @alice = agents(:alice)
    @bob = agents(:bob)
    # Remove fixture plan so tests start clean for alice
    plans(:alice_active_plan).destroy
  end

  test "create_plan creates a new active plan" do
    plan = PlanService.create_plan(
      agent: @alice,
      goal: "Make friends",
      steps: [ "Visit Town Square", "Talk to someone" ],
      tick: 20
    )

    assert plan.persisted?
    assert_equal "active", plan.status
    assert_equal "Make friends", plan.goal
    assert_equal 20, plan.created_at_tick
    assert_equal 20, plan.last_updated_at_tick
    assert_equal 2, plan.steps.size
    assert_equal "Visit Town Square", plan.steps.first["description"]
    assert_equal false, plan.steps.first["done"]
  end

  test "create_plan normalizes string steps to objects" do
    plan = PlanService.create_plan(
      agent: @alice,
      goal: "Explore",
      steps: [ "Step one", "Step two" ],
      tick: 20
    )

    plan.steps.each do |step|
      assert step.key?("description")
      assert step.key?("done")
      assert_equal false, step["done"]
    end
  end

  test "create_plan normalizes object steps" do
    plan = PlanService.create_plan(
      agent: @alice,
      goal: "Explore",
      steps: [ { "description" => "Step one", "done" => true } ],
      tick: 20
    )

    assert_equal "Step one", plan.steps.first["description"]
    assert_equal true, plan.steps.first["done"]
  end

  test "create_plan emits plan_created event" do
    assert_difference "Event.where(event_type: 'plan_created').count" do
      PlanService.create_plan(
        agent: @alice,
        goal: "Make friends",
        steps: [],
        tick: 20
      )
    end

    event = Event.where(event_type: "plan_created", agent: @alice).order(created_at: :desc).first
    assert_equal "Make friends", event.payload["goal"]
  end

  test "create_plan auto-abandons existing active plan" do
    first_plan = PlanService.create_plan(
      agent: @alice,
      goal: "First plan",
      steps: [],
      tick: 20
    )

    second_plan = PlanService.create_plan(
      agent: @alice,
      goal: "Second plan",
      steps: [],
      tick: 25
    )

    first_plan.reload
    assert_equal "abandoned", first_plan.status
    assert_equal "active", second_plan.status
    assert_equal second_plan, @alice.active_plan
  end

  test "update_plan updates goal and steps" do
    plan = PlanService.create_plan(agent: @alice, goal: "Original", steps: [], tick: 20)

    PlanService.update_plan(
      plan: plan,
      tick: 30,
      goal: "Updated goal",
      steps: [ "New step" ]
    )

    plan.reload
    assert_equal "Updated goal", plan.goal
    assert_equal 30, plan.last_updated_at_tick
    assert_equal 1, plan.steps.size
  end

  test "update_plan emits plan_updated event" do
    plan = PlanService.create_plan(agent: @alice, goal: "Original", steps: [], tick: 20)

    assert_difference "Event.where(event_type: 'plan_updated').count" do
      PlanService.update_plan(plan: plan, tick: 30, goal: "Updated")
    end
  end

  test "update_plan raises error for non-active plan" do
    plan = PlanService.create_plan(agent: @alice, goal: "Test", steps: [], tick: 20)
    PlanService.complete_plan(plan: plan, tick: 25)

    assert_raises(PlanService::PlanError) do
      PlanService.update_plan(plan: plan, tick: 30, goal: "Oops")
    end
  end

  test "complete_plan sets status to completed" do
    plan = PlanService.create_plan(agent: @alice, goal: "Test", steps: [], tick: 20)
    PlanService.complete_plan(plan: plan, tick: 30)

    plan.reload
    assert_equal "completed", plan.status
    assert_equal 30, plan.last_updated_at_tick
  end

  test "complete_plan emits plan_completed event" do
    plan = PlanService.create_plan(agent: @alice, goal: "Test", steps: [], tick: 20)

    assert_difference "Event.where(event_type: 'plan_completed').count" do
      PlanService.complete_plan(plan: plan, tick: 30)
    end
  end

  test "complete_plan raises error for non-active plan" do
    plan = PlanService.create_plan(agent: @alice, goal: "Test", steps: [], tick: 20)
    PlanService.abandon_plan(plan: plan, tick: 25)

    assert_raises(PlanService::PlanError) do
      PlanService.complete_plan(plan: plan, tick: 30)
    end
  end

  test "abandon_plan sets status to abandoned" do
    plan = PlanService.create_plan(agent: @alice, goal: "Test", steps: [], tick: 20)
    PlanService.abandon_plan(plan: plan, tick: 30)

    plan.reload
    assert_equal "abandoned", plan.status
    assert_equal 30, plan.last_updated_at_tick
  end

  test "abandon_plan emits plan_abandoned event with reason" do
    plan = PlanService.create_plan(agent: @alice, goal: "Test", steps: [], tick: 20)

    assert_difference "Event.where(event_type: 'plan_abandoned').count" do
      PlanService.abandon_plan(plan: plan, tick: 30, reason: "changed_mind")
    end

    event = Event.where(event_type: "plan_abandoned").order(created_at: :desc).first
    assert_equal "changed_mind", event.payload["reason"]
  end

  test "abandon_plan is a no-op for non-active plans" do
    plan = PlanService.create_plan(agent: @alice, goal: "Test", steps: [], tick: 20)
    PlanService.complete_plan(plan: plan, tick: 25)

    assert_no_difference "Event.where(event_type: 'plan_abandoned').count" do
      PlanService.abandon_plan(plan: plan, tick: 30)
    end
  end

  test "on_tick abandons stale plans" do
    plan = PlanService.create_plan(agent: @alice, goal: "Old plan", steps: [], tick: 10)

    PlanService.on_tick(211)

    plan.reload
    assert_equal "abandoned", plan.status

    event = Event.where(event_type: "plan_abandoned", agent: @alice).order(created_at: :desc).first
    assert_equal "stale", event.payload["reason"]
  end

  test "on_tick does not abandon recently updated plans" do
    plan = PlanService.create_plan(agent: @alice, goal: "Fresh plan", steps: [], tick: 100)

    PlanService.on_tick(200)

    plan.reload
    assert_equal "active", plan.status
  end
end
