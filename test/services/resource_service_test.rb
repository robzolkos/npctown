require "test_helper"

class ResourceServiceTest < ActiveSupport::TestCase
  # --- Energy Decay ---

  test "decay_energy reduces energy by 1 for active agents" do
    agent = agents(:alice)
    agent.update_column(:energy, 50)

    ResourceService.on_tick(10)

    assert_equal 49, agent.reload.energy
  end

  test "decay_energy doubles when food is 0 (starvation)" do
    agent = agents(:alice)
    agent.update_columns(energy: 50, food: 0)

    ResourceService.on_tick(10)

    assert_equal 48, agent.reload.energy
  end

  test "decay_energy emits event when energy hits 0" do
    agent = agents(:alice)
    agent.update_column(:energy, 1)

    assert_difference "Event.where(event_type: 'resource_changed').count" do
      ResourceService.on_tick(10)
    end

    assert_equal 0, agent.reload.energy
    event = Event.where(event_type: "resource_changed").order(created_at: :desc).first
    assert_equal "exhausted", event.payload["reason"]
  end

  test "decay_energy skips agents already at 0" do
    agent = agents(:alice)
    agent.update_column(:energy, 0)

    assert_no_difference "Event.where(event_type: 'resource_changed').count" do
      ResourceService.on_tick(10)
    end

    assert_equal 0, agent.reload.energy
  end

  # --- Food Decay ---

  test "decay_food reduces food by 1 for active agents" do
    agent = agents(:alice)
    agent.update_column(:food, 30)

    ResourceService.on_tick(20)

    assert_equal 29, agent.reload.food
  end

  test "decay_food emits event when food hits 0" do
    agent = agents(:alice)
    agent.update_column(:food, 1)

    assert_difference "Event.where(event_type: 'resource_changed').count" do
      ResourceService.on_tick(20)
    end

    assert_equal 0, agent.reload.food
    event = Event.where(event_type: "resource_changed").order(created_at: :desc).first
    assert_equal "starving", event.payload["reason"]
  end

  # --- Market Bonus ---

  test "market_bonus adds food and currency to agents at commerce locations" do
    bob = agents(:bob) # bob is at Market (commerce location)
    # Tick 720 also triggers decay (energy -1, food -1), so account for both
    original_food = bob.food
    original_currency = bob.currency

    ResourceService.on_tick(720)

    bob.reload
    # food: -1 (decay) +10 (bonus) = +9 net
    assert_equal original_food - 1 + 10, bob.food
    assert_equal original_currency + 10, bob.currency
  end

  test "market_bonus skips agents not at commerce locations" do
    alice = agents(:alice) # alice is at Town Square (social)
    original_food = alice.food
    original_currency = alice.currency

    ResourceService.on_tick(720)

    alice.reload
    # food decays by 1 (tick 720 is divisible by 20), no market bonus
    assert_equal original_food - 1, alice.food
    assert_equal original_currency, alice.currency
  end

  test "market_bonus emits resource_changed event with market_bonus reason" do
    ResourceService.on_tick(720)

    market_event = Event.where(event_type: "resource_changed")
                        .order(created_at: :desc)
                        .detect { |e| e.payload["reason"] == "market_bonus" }
    assert_not_nil market_event
    assert_equal agents(:bob).id, market_event.agent_id
  end

  # --- Rest ---

  test "rest restores energy" do
    agent = agents(:alice)
    agent.update_column(:energy, 50)

    ResourceService.rest(agent: agent, tick: 1)

    assert_equal 80, agent.reload.energy
  end

  test "rest caps energy at 100" do
    agent = agents(:alice)
    agent.update_column(:energy, 90)

    ResourceService.rest(agent: agent, tick: 1)

    assert_equal 100, agent.reload.energy
  end

  test "rest emits resource_changed event" do
    agent = agents(:alice)
    agent.update_column(:energy, 50)

    assert_difference "Event.where(event_type: 'resource_changed').count" do
      ResourceService.rest(agent: agent, tick: 1)
    end

    event = Event.where(event_type: "resource_changed").order(created_at: :desc).first
    assert_equal "rest", event.payload["reason"]
  end

  # --- Eat ---

  test "eat consumes food and restores energy" do
    agent = agents(:alice)
    agent.update_columns(food: 50, energy: 30)

    ResourceService.eat(agent: agent, tick: 1)

    agent.reload
    assert_equal 30, agent.food
    assert_equal 70, agent.energy
  end

  test "eat caps energy at 100" do
    agent = agents(:alice)
    agent.update_columns(food: 50, energy: 80)

    ResourceService.eat(agent: agent, tick: 1)

    assert_equal 100, agent.reload.energy
  end

  test "eat raises when food is insufficient" do
    agent = agents(:alice)
    agent.update_column(:food, 10)

    assert_raises(ActionService::ActionError) do
      ResourceService.eat(agent: agent, tick: 1)
    end
  end

  # --- Trade ---

  test "trade transfers resource between agents at same location" do
    alice = agents(:alice)
    charlie = agents(:charlie) # both at Town Square

    ResourceService.trade(agent: alice, target: charlie, resource: "currency", amount: 25, tick: 1)

    assert_equal 75, alice.reload.currency
    assert_equal 125, charlie.reload.currency
  end

  test "trade emits resource_changed event with trade reason" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    assert_difference "Event.where(event_type: 'resource_changed').count" do
      ResourceService.trade(agent: alice, target: charlie, resource: "currency", amount: 25, tick: 1)
    end

    event = Event.where(event_type: "resource_changed").order(created_at: :desc).first
    assert_equal "trade", event.payload["reason"]
    assert_equal charlie.id, event.payload["target_agent_id"]
  end

  test "trade raises when agents are at different locations" do
    alice = agents(:alice)  # Town Square
    bob = agents(:bob)      # Market

    assert_raises(ActionService::ActionError) do
      ResourceService.trade(agent: alice, target: bob, resource: "currency", amount: 10, tick: 1)
    end
  end

  test "trade raises when agent has insufficient resource" do
    alice = agents(:alice)
    charlie = agents(:charlie)
    alice.update_column(:currency, 5)

    assert_raises(ActionService::ActionError) do
      ResourceService.trade(agent: alice, target: charlie, resource: "currency", amount: 10, tick: 1)
    end
  end

  test "trade raises for invalid resource name" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    assert_raises(ActionService::ActionError) do
      ResourceService.trade(agent: alice, target: charlie, resource: "gold", amount: 10, tick: 1)
    end
  end

  test "trade raises when amount exceeds maximum" do
    alice = agents(:alice)
    charlie = agents(:charlie)

    assert_raises(ActionService::ActionError) do
      ResourceService.trade(agent: alice, target: charlie, resource: "currency", amount: 51, tick: 1)
    end
  end

  # --- Resource Descriptions ---

  test "resource_description returns approximate labels" do
    agent = agents(:alice) # food: 50, energy: 100, currency: 100
    labels = ResourceService.resource_description(agent)

    assert_equal 3, labels.length
    assert_equal "fed", labels[0]
    assert_equal "energetic", labels[1]
    assert_equal "modest", labels[2]
  end

  test "resource_description labels for low resources" do
    agent = agents(:alice)
    agent.update_columns(food: 5, energy: 0, currency: 10)

    labels = ResourceService.resource_description(agent)
    assert_equal "starving", labels[0]
    assert_equal "exhausted", labels[1]
    assert_equal "poor", labels[2]
  end

  # --- No-op on non-matching ticks ---

  test "on_tick does nothing on non-interval ticks" do
    agent = agents(:alice)
    original_energy = agent.energy
    original_food = agent.food

    ResourceService.on_tick(7)

    agent.reload
    assert_equal original_energy, agent.energy
    assert_equal original_food, agent.food
  end
end
