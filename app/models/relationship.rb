class Relationship < ApplicationRecord
  include PrefixedId
  has_prefixed_id prefix: "rel"

  DIMENSION_RANGE = -100..100
  FAMILIARITY_RANGE = 0..100

  LABELS = {
    close_friend: "Close Friend",
    complicated: "It's Complicated",
    professional_rival: "Professional Rival",
    nemesis: "Nemesis",
    stranger: "Stranger",
    acquaintance: "Acquaintance"
  }.freeze

  belongs_to :agent
  belongs_to :target_agent, class_name: "Agent"

  validates :agent_id, uniqueness: { scope: :target_agent_id }
  validates :trust, numericality: { in: DIMENSION_RANGE }
  validates :affection, numericality: { in: DIMENSION_RANGE }
  validates :respect, numericality: { in: DIMENSION_RANGE }
  validates :familiarity, numericality: { in: FAMILIARITY_RANGE }
  validate :not_self_referencing

  scope :for_agent, ->(agent) { where(agent: agent) }

  def label
    return LABELS[:stranger] if familiarity < 10
    return LABELS[:acquaintance] if familiarity < 30

    if trust < -50 && affection < -50 && respect < -50
      LABELS[:nemesis]
    elsif respect > 30 && affection < -10
      LABELS[:professional_rival]
    elsif trust < 0 && affection > 30
      LABELS[:complicated]
    elsif trust > 30 && affection > 30
      LABELS[:close_friend]
    else
      LABELS[:acquaintance]
    end
  end

  private

  def not_self_referencing
    if agent_id == target_agent_id
      errors.add(:target_agent, "cannot be the same as agent")
    end
  end
end
