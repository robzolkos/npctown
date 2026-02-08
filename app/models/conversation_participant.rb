class ConversationParticipant < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "cp"

  belongs_to :conversation
  belongs_to :agent

  validates :joined_at_tick, presence: true
  validates :agent_id, uniqueness: { scope: :conversation_id }

  scope :active, -> { where(left_at_tick: nil) }
end
