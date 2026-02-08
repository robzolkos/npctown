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
end
