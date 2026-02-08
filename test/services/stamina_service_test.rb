require "test_helper"

class StaminaServiceTest < ActiveSupport::TestCase
  setup do
    @test_key = "npctown:stamina:regen_counter:test:#{Process.pid}"
    StaminaService.redis_key = @test_key
    Sidekiq.redis { |c| c.del(@test_key) }
  end

  teardown do
    Sidekiq.redis { |c| c.del(@test_key) }
    StaminaService.redis_key = nil
  end

  test "does not regen before REGEN_INTERVAL ticks" do
    agent = agents(:alice)
    agent.update_column(:stamina, 50)

    # Set counter to 178 (two short of interval)
    Sidekiq.redis { |c| c.set(@test_key, 178) }
    StaminaService.on_tick(1)

    assert_equal 50, agent.reload.stamina
  end

  test "regens +1 stamina after REGEN_INTERVAL ticks" do
    agent = agents(:alice)
    agent.update_column(:stamina, 50)

    # Set counter to 179 so next tick triggers regen
    Sidekiq.redis { |c| c.set(@test_key, 179) }
    StaminaService.on_tick(1)

    assert_equal 51, agent.reload.stamina
  end

  test "caps stamina at MAX_STAMINA" do
    agent = agents(:alice)
    agent.update_column(:stamina, 100)

    Sidekiq.redis { |c| c.set(@test_key, 179) }
    StaminaService.on_tick(1)

    assert_equal 100, agent.reload.stamina
  end

  test "counter resets after granting stamina" do
    agent = agents(:alice)
    agent.update_column(:stamina, 50)

    # First cycle
    Sidekiq.redis { |c| c.set(@test_key, 179) }
    StaminaService.on_tick(1)
    assert_equal 51, agent.reload.stamina

    # Counter should be reset to 0, so next tick shouldn't regen
    StaminaService.on_tick(2)
    assert_equal 51, agent.reload.stamina
  end
end
