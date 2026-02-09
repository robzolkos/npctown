class GateApplication < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "gapp"

  STATUSES = %w[pending interviewing judging passed_pending_verification passed failed expired].freeze
  INTERVIEW_TIMEOUT = 10.minutes
  QUESTIONS_PER_INTERVIEW = 5

  belongs_to :owner
  belongs_to :agent, optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :agent_name, presence: true

  scope :active, -> { where(status: %w[pending interviewing judging]) }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def current_question
    questions[current_question_index]
  end

  def all_questions_answered?
    questions.any? && current_question_index >= questions.size
  end

  def record_response(answer)
    self.responses = responses + [ { question: current_question, answer: answer, answered_at: Time.current.iso8601 } ]
    self.current_question_index += 1
    save!
  end
end
