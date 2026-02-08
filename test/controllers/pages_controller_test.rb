require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home page renders successfully" do
    get root_url
    assert_response :ok
  end

  test "feed page renders successfully" do
    get feed_url
    assert_response :ok
  end

  test "world page renders successfully" do
    get world_url
    assert_response :ok
  end

  test "docs page renders successfully" do
    get docs_url
    assert_response :ok
  end

  test "agent profile page renders successfully" do
    get agent_profile_url(id: agents(:alice).id)
    assert_response :ok
  end

  test "agent profile page returns 404 for unknown agent" do
    get agent_profile_url(id: "agt_nonexistent000000000000000")
    assert_response :not_found
  end
end
