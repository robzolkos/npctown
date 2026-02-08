class Conversation < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "conv"

  STATUSES = %w[active ended].freeze

  belongs_to :location
  has_many :conversation_participants, dependent: :destroy
  has_many :agents, through: :conversation_participants
  has_many :conversation_messages, dependent: :destroy

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :started_at_tick, presence: true

  scope :active, -> { where(status: "active") }
  scope :at_location, ->(location) { where(location: location) }

  def active_participants
    conversation_participants.where(left_at_tick: nil)
  end

  def last_message_tick
    conversation_messages.maximum(:tick)
  end

  def stale?(current_tick, threshold: 5)
    last_tick = last_message_tick || started_at_tick
    current_tick - last_tick >= threshold
  end
end
