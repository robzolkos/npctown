require "test_helper"

class LocationTest < ActiveSupport::TestCase
  test "valid location" do
    loc = Location.new(name: "New Place", description: "A place", location_type: "social")
    assert loc.valid?
  end

  test "requires name" do
    loc = Location.new(location_type: "social")
    assert_not loc.valid?
    assert_includes loc.errors[:name], "can't be blank"
  end

  test "requires unique name" do
    loc = Location.new(name: "Town Square", location_type: "social")
    assert_not loc.valid?
    assert_includes loc.errors[:name], "has already been taken"
  end

  test "validates location_type inclusion" do
    loc = Location.new(name: "Bad", location_type: "invalid")
    assert_not loc.valid?
    assert_includes loc.errors[:location_type], "is not included in the list"
  end

  test "has agents" do
    loc = locations(:town_square)
    assert_includes loc.agents, agents(:alice)
  end

  test "by_type scope" do
    social = Location.by_type("social")
    assert social.all? { |l| l.location_type == "social" }
  end
end
