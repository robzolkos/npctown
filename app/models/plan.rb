class Plan < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "plan"

  STATUSES = %w[active completed abandoned].freeze

  belongs_to :agent

  validates :goal, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :created_at_tick, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :last_updated_at_tick, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(status: "active") }
  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :recent, -> { order(created_at_tick: :desc) }

  def stale?(current_tick, threshold: 200)
    current_tick - last_updated_at_tick >= threshold
  end
end
