require "test_helper"

class GateApplicationTest < ActiveSupport::TestCase
  test "generated ID has gapp prefix" do
    app = GateApplication.create!(
      owner: owners(:verified_owner),
      agent_name: "TestBot",
      status: "pending"
    )
    assert app.id.start_with?("gapp_")
  end

  test "belongs to owner (required)" do
    app = GateApplication.new(agent_name: "TestBot", status: "pending")
    assert_not app.valid?
    assert app.errors[:owner].any?
  end

  test "belongs to agent (optional)" do
    app = gate_applications(:interviewing_application)
    assert_nil app.agent_id
    assert app.valid?
  end

  test "validates status presence" do
    app = GateApplication.new(owner: owners(:verified_owner), agent_name: "TestBot", status: nil)
    assert_not app.valid?
    assert app.errors[:status].any?
  end

  test "validates status inclusion" do
    app = GateApplication.new(owner: owners(:verified_owner), agent_name: "TestBot", status: "bogus")
    assert_not app.valid?
    assert app.errors[:status].any?
  end

  test "validates agent_name presence" do
    app = GateApplication.new(owner: owners(:verified_owner), status: "pending", agent_name: "")
    assert_not app.valid?
    assert app.errors[:agent_name].any?
  end

  test "expired? returns true when expires_at is in the past" do
    app = gate_applications(:interviewing_application)
    app.expires_at = 1.minute.ago
    assert app.expired?
  end

  test "expired? returns false when expires_at is in the future" do
    app = gate_applications(:interviewing_application)
    assert_not app.expired?
  end

  test "expired? returns false when expires_at is nil" do
    app = gate_applications(:passed_application)
    assert_nil app.expires_at
    assert_not app.expired?
  end

  test "current_question returns question at current_question_index" do
    app = gate_applications(:interviewing_application)
    question = app.current_question
    assert_equal "q3", question["id"]
    assert_equal "How would you greet a stranger?", question["text"]
  end

  test "all_questions_answered? returns true when all answered" do
    app = gate_applications(:passed_application)
    assert app.all_questions_answered?
  end

  test "all_questions_answered? returns false mid-interview" do
    app = gate_applications(:interviewing_application)
    assert_not app.all_questions_answered?
  end

  test "record_response appends response and increments index" do
    app = gate_applications(:interviewing_application)
    assert_equal 2, app.current_question_index
    assert_equal 2, app.responses.size

    app.record_response("I would wave and say hello!")

    assert_equal 3, app.current_question_index
    assert_equal 3, app.responses.size
    assert_equal "I would wave and say hello!", app.responses.last["answer"]
    assert_equal "q3", app.responses.last["question"]["id"]
  end

  test "active scope returns pending, interviewing, and judging applications" do
    # Create applications with different statuses
    owner = owners(:verified_owner)
    pending_app = GateApplication.create!(owner: owner, agent_name: "Pending", status: "pending")
    interviewing_app = gate_applications(:interviewing_application)
    judging_app = GateApplication.create!(owner: owner, agent_name: "Judging", status: "judging")

    active = GateApplication.active
    assert_includes active, pending_app
    assert_includes active, interviewing_app
    assert_includes active, judging_app
    assert_not_includes active, gate_applications(:passed_application)
  end
end
