require "test_helper"

class GateApplication::QuestionBankTest < ActiveSupport::TestCase
  test "QUESTIONS contains exactly 25 entries" do
    assert_equal 25, GateApplication::QuestionBank::QUESTIONS.size
  end

  test "each question has id, category, and text keys" do
    GateApplication::QuestionBank::QUESTIONS.each do |q|
      assert q.key?(:id), "Question missing :id"
      assert q.key?(:category), "Question missing :category"
      assert q.key?(:text), "Question missing :text"
    end
  end

  test "all 5 categories have exactly 5 questions each" do
    by_category = GateApplication::QuestionBank::QUESTIONS.group_by { |q| q[:category] }
    assert_equal 5, by_category.size
    GateApplication::QuestionBank::CATEGORIES.each do |cat|
      assert_equal 5, by_category[cat].size, "Category #{cat} should have 5 questions"
    end
  end

  test "all question IDs are unique" do
    ids = GateApplication::QuestionBank::QUESTIONS.map { |q| q[:id] }
    assert_equal ids.size, ids.uniq.size
  end

  test "select_questions returns exactly 5 questions" do
    selected = GateApplication::QuestionBank.select_questions
    assert_equal 5, selected.size
  end

  test "select_questions includes at least 1 question per category" do
    selected = GateApplication::QuestionBank.select_questions
    categories = selected.map { |q| q[:category] }.uniq.sort
    assert_equal GateApplication::QuestionBank::CATEGORIES.sort, categories
  end

  test "select_questions returns different sets across calls" do
    sets = 10.times.map { GateApplication::QuestionBank.select_questions.map { |q| q[:id] }.sort }
    assert sets.uniq.size > 1, "Expected different question sets across 10 calls"
  end
end
