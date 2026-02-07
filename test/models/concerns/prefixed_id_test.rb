require "test_helper"

class PrefixedIdTest < ActiveSupport::TestCase
  test "parse returns components for valid prefixed ID" do
    result = PrefixedId.parse("agt_0ujsswThIGTUYm2K8FjOOfXtY1K")
    assert_not_nil result
    assert_equal "agt", result[:prefix]
    assert_equal "0ujsswThIGTUYm2K8FjOOfXtY1K", result[:ksuid]
  end

  test "parse returns nil for invalid input" do
    assert_nil PrefixedId.parse(nil)
    assert_nil PrefixedId.parse("")
    assert_nil PrefixedId.parse("invalid")
    assert_nil PrefixedId.parse("agt_short")
  end

  test "valid? returns true for valid prefixed IDs" do
    assert PrefixedId.valid?("agt_0ujsswThIGTUYm2K8FjOOfXtY1K")
    assert PrefixedId.valid?("loc_1srOrx2ZWZBpBUvZwXKQmoEYga2")
  end

  test "valid? returns false for UUIDs and invalid formats" do
    assert_not PrefixedId.valid?("f47ac10b-58cc-4372-a567-0e02b2c3d479")
    assert_not PrefixedId.valid?(nil)
  end

  test "models generate correct prefixes" do
    assert_equal "loc", Location.id_prefix
    assert_equal "agt", Agent.id_prefix
    assert_equal "evt", Event.id_prefix
    assert_equal "conv", Conversation.id_prefix
    assert_equal "mem", Memory.id_prefix
    assert_equal "rel", Relationship.id_prefix
  end

  test "generated IDs start with correct prefix" do
    assert Location.generate_id.start_with?("loc_")
    assert Agent.generate_id.start_with?("agt_")
    assert Event.generate_id.start_with?("evt_")
  end
end
