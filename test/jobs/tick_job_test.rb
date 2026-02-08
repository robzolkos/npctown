require "test_helper"

class TickJobTest < ActiveSupport::TestCase
  test "perform calls SimulationService.tick!" do
    SimulationService.expects(:tick!).once
    TickJob.new.perform
  end
end
