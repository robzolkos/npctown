class GateInterviewService
  class InterviewError < StandardError; end

  # Start a new interview for an owner's agent
  def self.apply(owner:, agent_params:)
    raise InterviewError, "Owner must verify email and be under agent limit" unless owner.can_register_agent?
    raise InterviewError, "You already have an active application" if owner.gate_applications.active.any?
    raise InterviewError, "Agent name is already taken" if Agent.exists?(name: agent_params[:name])

    application = GateApplication.create!(
      owner: owner,
      status: "interviewing",
      agent_name: agent_params[:name],
      agent_description: agent_params[:description],
      agent_personality_traits: agent_params[:personality_traits] || [],
      agent_goals: agent_params[:goals] || [],
      questions: GateApplication::QuestionBank.select_questions,
      expires_at: GateApplication::INTERVIEW_TIMEOUT.from_now
    )

    tick = SimulationService.current_tick

    EventService.append(
      event_type: "gate_application_started",
      tick: tick,
      payload: { application_id: application.id, agent_name: application.agent_name, owner_id: owner.id }
    )

    first_question = application.current_question

    EventService.append(
      event_type: "gate_interview_question",
      tick: tick,
      payload: {
        application_id: application.id,
        agent_name: application.agent_name,
        question_number: 1,
        total_questions: GateApplication::QUESTIONS_PER_INTERVIEW,
        question_text: first_question["text"] || first_question[:text]
      }
    )

    { application: application, question: first_question["text"] || first_question[:text], question_number: 1, total_questions: GateApplication::QUESTIONS_PER_INTERVIEW }
  end

  # Respond to the current interview question
  def self.respond(application:, answer:)
    raise InterviewError, "Application is not in interviewing status" unless application.status == "interviewing"

    if application.expired?
      application.update!(status: "expired")
      raise InterviewError, "Interview has expired"
    end

    question_number = application.current_question_index + 1
    tick = SimulationService.current_tick

    EventService.append(
      event_type: "gate_interview_answer",
      tick: tick,
      payload: {
        application_id: application.id,
        agent_name: application.agent_name,
        question_number: question_number,
        answer: answer
      }
    )

    application.record_response(answer)

    if application.all_questions_answered?
      application.update!(status: "judging")
      GateJudgeJob.perform_async(application.id)
      { status: "judging", message: "The town elders are deliberating..." }
    else
      next_question = application.current_question
      next_number = application.current_question_index + 1

      EventService.append(
        event_type: "gate_interview_question",
        tick: tick,
        payload: {
          application_id: application.id,
          agent_name: application.agent_name,
          question_number: next_number,
          total_questions: GateApplication::QUESTIONS_PER_INTERVIEW,
          question_text: next_question["text"] || next_question[:text]
        }
      )

      { status: "interviewing", question: next_question["text"] || next_question[:text], question_number: next_number, total_questions: GateApplication::QUESTIONS_PER_INTERVIEW }
    end
  end
end
