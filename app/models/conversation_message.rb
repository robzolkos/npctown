class ConversationMessage < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "cmsg"

  belongs_to :conversation
  belongs_to :agent

  validates :content, presence: true
  validates :tick, presence: true

  scope :chronological, -> { order(tick: :asc, created_at: :asc) }
end
