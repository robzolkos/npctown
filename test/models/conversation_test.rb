require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "has participants and messages" do
    conv = conversations(:active_conversation)
    assert conv.agents.include?(agents(:alice))
    assert conv.conversation_messages.any?
  end

  test "validates status" do
    conv = Conversation.new(status: "invalid", location: locations(:town_square), started_at_tick: 1)
    assert_not conv.valid?
  end

  test "active scope" do
    assert Conversation.active.all? { |c| c.status == "active" }
  end

  test "requires started_at_tick" do
    conv = Conversation.new(location: locations(:town_square), status: "active")
    assert_not conv.valid?
  end
end
