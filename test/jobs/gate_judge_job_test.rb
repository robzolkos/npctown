require "test_helper"

class GateJudgeJobTest < ActiveSupport::TestCase
  setup do
    @owner = owners(:verified_owner)
    @owner.gate_applications.active.destroy_all

    @application = GateApplication.create!(
      owner: @owner,
      status: "judging",
      agent_name: "JudgeJobTestAgent",
      agent_description: "A test agent for judging",
      agent_personality_traits: [ "curious", "brave" ],
      agent_goals: [ "explore the town" ],
      questions: [
        { "id" => "q1", "category" => "intent", "text" => "Why do you want to join?" },
        { "id" => "q2", "category" => "identity", "text" => "Describe yourself." },
        { "id" => "q3", "category" => "social", "text" => "How would you greet a stranger?" },
        { "id" => "q4", "category" => "creativity", "text" => "Tell me a story." },
        { "id" => "q5", "category" => "ethics", "text" => "What would you do if you found something valuable?" }
      ],
      responses: [
        { "question" => { "id" => "q1", "category" => "intent", "text" => "Why do you want to join?" }, "answer" => "I want to explore.", "answered_at" => "2026-02-08T12:00:30Z" },
        { "question" => { "id" => "q2", "category" => "identity", "text" => "Describe yourself." }, "answer" => "I am curious.", "answered_at" => "2026-02-08T12:01:00Z" },
        { "question" => { "id" => "q3", "category" => "social", "text" => "How would you greet a stranger?" }, "answer" => "Hello friend!", "answered_at" => "2026-02-08T12:01:30Z" },
        { "question" => { "id" => "q4", "category" => "creativity", "text" => "Tell me a story." }, "answer" => "Once upon a time...", "answered_at" => "2026-02-08T12:02:00Z" },
        { "question" => { "id" => "q5", "category" => "ethics", "text" => "What would you do if you found something valuable?" }, "answer" => "Return it.", "answered_at" => "2026-02-08T12:02:30Z" }
      ],
      current_question_index: 5
    )

    SimulationService.stubs(:current_tick).returns(42)
  end

  test "perform creates agent and updates application on pass" do
    GateJudgeService.stubs(:evaluate).returns({ passed: true, reasoning: "Great candidate", method: "heuristic" })

    assert_difference "Agent.count", 1 do
      GateJudgeJob.new.perform(@application.id)
    end

    @application.reload
    assert_equal "passed_pending_verification", @application.status
    assert_equal "Great candidate", @application.judge_reasoning
    assert @application.agent_id.present?
  end

  test "perform places agent in Town Square with idle status" do
    GateJudgeService.stubs(:evaluate).returns({ passed: true, reasoning: "Good", method: "heuristic" })

    GateJudgeJob.new.perform(@application.id)

    agent = @application.reload.agent
    assert_equal "Town Square", agent.location.name
    assert_equal "idle", agent.status
    assert_equal @owner, agent.owner
    assert_equal "JudgeJobTestAgent", agent.name
    assert agent.probation_until.present?
    assert agent.probation_until > 23.hours.from_now
  end

  test "perform caches API key in Redis on pass" do
    GateJudgeService.stubs(:evaluate).returns({ passed: true, reasoning: "Good", method: "heuristic" })

    GateJudgeJob.new.perform(@application.id)

    cached_key = Sidekiq.redis { |conn| conn.get("gate:api_key:#{@application.id}") }
    assert cached_key.present?
    assert cached_key.start_with?("npc_")
  end

  test "perform emits gate_application_passed event on pass" do
    GateJudgeService.stubs(:evaluate).returns({ passed: true, reasoning: "Good", method: "heuristic" })

    assert_difference -> { Event.where(event_type: "gate_application_passed").count }, 1 do
      GateJudgeJob.new.perform(@application.id)
    end
  end

  test "perform updates status to failed on rejection" do
    GateJudgeService.stubs(:evaluate).returns({ passed: false, reasoning: "Low quality", method: "heuristic" })

    assert_no_difference "Agent.count" do
      GateJudgeJob.new.perform(@application.id)
    end

    @application.reload
    assert_equal "failed", @application.status
    assert_equal "Low quality", @application.judge_reasoning
    assert_nil @application.agent_id
  end

  test "perform emits gate_application_failed event on rejection" do
    GateJudgeService.stubs(:evaluate).returns({ passed: false, reasoning: "Bad", method: "heuristic" })

    assert_difference -> { Event.where(event_type: "gate_application_failed").count }, 1 do
      GateJudgeJob.new.perform(@application.id)
    end
  end

  test "perform is idempotent for non-judging applications" do
    @application.update!(status: "failed")

    assert_no_difference "Agent.count" do
      assert_no_difference "Event.count" do
        GateJudgeJob.new.perform(@application.id)
      end
    end
  end
end
