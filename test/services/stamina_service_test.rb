require "test_helper"

class StaminaServiceTest < ActiveSupport::TestCase
  test "on_tick regenerates stamina for active agents below max" do
    agent = agents(:alice)
    agent.update_column(:stamina, 50)

    StaminaService.on_tick(1)

    assert_equal 52, agent.reload.stamina
  end

  test "on_tick caps stamina at 100" do
    agent = agents(:alice)
    agent.update_column(:stamina, 99)

    StaminaService.on_tick(1)

    assert_equal 100, agent.reload.stamina
  end

  test "on_tick skips agents already at max stamina" do
    agent = agents(:alice)
    agent.update_column(:stamina, 100)

    StaminaService.on_tick(1)

    assert_equal 100, agent.reload.stamina
  end
end
