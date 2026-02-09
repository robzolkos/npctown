require "test_helper"

class GateInterviewServiceTest < ActiveSupport::TestCase
  setup do
    @owner = owners(:verified_owner)
    @agent_params = {
      name: "GateTestAgent",
      description: "A test agent for the interview",
      personality_traits: [ "curious", "brave" ],
      goals: [ "explore the town" ]
    }
    # Clear existing active applications from fixtures so apply tests can create fresh ones
    @owner.gate_applications.active.destroy_all
    SimulationService.stubs(:current_tick).returns(42)
  end

  # --- apply tests ---

  test "apply creates application and returns first question" do
    result = GateInterviewService.apply(owner: @owner, agent_params: @agent_params)

    assert result[:application].persisted?
    assert_equal "interviewing", result[:application].status
    assert_equal "GateTestAgent", result[:application].agent_name
    assert_equal 1, result[:question_number]
    assert_equal 5, result[:total_questions]
    assert result[:question].present?
  end

  test "apply sets expires_at on application" do
    result = GateInterviewService.apply(owner: @owner, agent_params: @agent_params)

    assert result[:application].expires_at.present?
    assert result[:application].expires_at > Time.current
  end

  test "apply selects 5 questions from question bank" do
    result = GateInterviewService.apply(owner: @owner, agent_params: @agent_params)

    assert_equal 5, result[:application].questions.size
  end

  test "apply emits gate_application_started event" do
    assert_difference -> { Event.where(event_type: "gate_application_started").count }, 1 do
      GateInterviewService.apply(owner: @owner, agent_params: @agent_params)
    end
  end

  test "apply emits first gate_interview_question event" do
    assert_difference -> { Event.where(event_type: "gate_interview_question").count }, 1 do
      GateInterviewService.apply(owner: @owner, agent_params: @agent_params)
    end
  end

  test "apply raises when owner cannot register agent" do
    unverified = owners(:unverified_owner)

    error = assert_raises(GateInterviewService::InterviewError) do
      GateInterviewService.apply(owner: unverified, agent_params: @agent_params)
    end
    assert_match(/verify email/, error.message)
  end

  test "apply raises when active application exists" do
    GateInterviewService.apply(owner: @owner, agent_params: @agent_params)

    error = assert_raises(GateInterviewService::InterviewError) do
      GateInterviewService.apply(owner: @owner, agent_params: { name: "AnotherAgent" })
    end
    assert_match(/active application/, error.message)
  end

  test "apply raises when agent name is taken" do
    existing_name = agents(:alice).name

    error = assert_raises(GateInterviewService::InterviewError) do
      GateInterviewService.apply(owner: @owner, agent_params: { name: existing_name })
    end
    assert_match(/already taken/, error.message)
  end

  # --- respond tests ---

  test "respond records answer and returns next question" do
    application = create_fresh_application

    result = GateInterviewService.respond(application: application, answer: "I love exploring new places.")

    assert_equal "interviewing", result[:status]
    assert_equal 2, result[:question_number]
    assert_equal 5, result[:total_questions]
    assert result[:question].present?
  end

  test "respond emits gate_interview_answer event" do
    application = create_fresh_application

    assert_difference -> { Event.where(event_type: "gate_interview_answer").count }, 1 do
      GateInterviewService.respond(application: application, answer: "My answer.")
    end
  end

  test "respond emits gate_interview_question event for next question" do
    application = create_fresh_application

    assert_difference -> { Event.where(event_type: "gate_interview_question").count }, 1 do
      GateInterviewService.respond(application: application, answer: "My answer.")
    end
  end

  test "respond on final answer sets status to judging and enqueues job" do
    application = create_fresh_application

    # Answer first 4 questions
    4.times do |i|
      GateInterviewService.respond(application: application, answer: "Answer #{i + 1}")
    end

    GateJudgeJob.expects(:perform_async).with(application.id).once

    result = GateInterviewService.respond(application: application, answer: "Final answer")

    assert_equal "judging", result[:status]
    assert_match(/deliberating/, result[:message])
    assert_equal "judging", application.reload.status
  end

  test "respond on final answer does not emit question event" do
    application = create_fresh_application

    4.times { |i| GateInterviewService.respond(application: application, answer: "Answer #{i + 1}") }

    GateJudgeJob.stubs(:perform_async)

    assert_no_difference -> { Event.where(event_type: "gate_interview_question").count } do
      GateInterviewService.respond(application: application, answer: "Final answer")
    end
  end

  test "respond raises when application is expired" do
    application = create_fresh_application
    application.update!(expires_at: 1.minute.ago)

    error = assert_raises(GateInterviewService::InterviewError) do
      GateInterviewService.respond(application: application, answer: "Too late")
    end
    assert_match(/expired/, error.message)
    assert_equal "expired", application.reload.status
  end

  test "respond raises when application is not interviewing" do
    application = create_fresh_application
    application.update!(status: "judging")

    error = assert_raises(GateInterviewService::InterviewError) do
      GateInterviewService.respond(application: application, answer: "Oops")
    end
    assert_match(/not in interviewing/, error.message)
  end

  private

  def create_fresh_application
    result = GateInterviewService.apply(owner: @owner, agent_params: @agent_params)
    result[:application]
  end
end
