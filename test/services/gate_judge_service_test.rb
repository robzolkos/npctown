require "test_helper"

class GateJudgeServiceTest < ActiveSupport::TestCase
  setup do
    @base_questions = [
      { "id" => "q1", "category" => "intent", "text" => "Why do you want to join?" },
      { "id" => "q2", "category" => "identity", "text" => "Describe yourself." },
      { "id" => "q3", "category" => "social", "text" => "How would you greet a stranger?" },
      { "id" => "q4", "category" => "creativity", "text" => "Tell me a story." },
      { "id" => "q5", "category" => "ethics", "text" => "What would you do if you found something valuable?" }
    ]
  end

  # --- Full evaluate tests ---

  test "evaluate returns heuristic pass for high-quality responses" do
    app = build_application(
      responses: build_good_responses,
      traits: [ "curious", "brave" ],
      goals: [ "explore the town" ]
    )

    result = GateJudgeService.evaluate(app)

    assert result[:passed]
    assert_equal "heuristic", result[:method]
    assert result[:reasoning].present?
  end

  test "evaluate returns heuristic fail for very short responses" do
    app = build_application(
      responses: build_responses_with_answers([ "yes", "no", "ok", "sure", "fine" ]),
      traits: [ "curious" ],
      goals: [ "explore" ]
    )

    result = GateJudgeService.evaluate(app)

    assert_not result[:passed]
    assert_equal "heuristic", result[:method]
  end

  test "evaluate returns heuristic fail for identical copy-pasted answers" do
    same_answer = "I just want to be here and do stuff in the town please let me in."
    app = build_application(
      responses: build_responses_with_answers([ same_answer ] * 5),
      traits: [ "curious" ],
      goals: [ "explore" ]
    )

    result = GateJudgeService.evaluate(app)

    assert_not result[:passed]
    assert_equal "heuristic", result[:method]
  end

  # --- Individual heuristic score tests ---

  test "score_response_length gives full score for long answers" do
    responses = build_responses_with_answers([ "a" * 60 ] * 5)
    score = GateJudgeService.send(:score_response_length, responses)
    assert_equal 20, score
  end

  test "score_response_length gives zero for all short answers" do
    responses = build_responses_with_answers([ "short" ] * 5)
    score = GateJudgeService.send(:score_response_length, responses)
    assert_equal 0, score
  end

  test "score_response_diversity gives low score for identical answers" do
    responses = build_responses_with_answers([ "the exact same answer repeated" ] * 5)
    score = GateJudgeService.send(:score_response_diversity, responses)
    assert score <= 5
  end

  test "score_response_diversity gives high score for diverse answers" do
    responses = build_responses_with_answers([
      "I want to explore and discover new places in this wonderful world",
      "My personality is defined by curiosity and a deep love of learning",
      "I would greet them warmly with a smile and introduce myself politely",
      "Once upon a time a brave knight traveled across mountains seeking wisdom",
      "Finding something valuable means returning it to the rightful owner immediately"
    ])
    score = GateJudgeService.send(:score_response_diversity, responses)
    assert score >= 14
  end

  test "score_keyword_relevance matches category keywords" do
    responses = build_responses_with_answers([
      "I want to join this community and find new friends here",
      "I would describe myself as someone who believes in growth",
      "I greet people warmly and help them feel welcome",
      "Let me imagine a story about a magical dream world",
      "I think being honest and choosing the right path matters most"
    ])
    score = GateJudgeService.send(:score_keyword_relevance, responses)
    assert score >= 16
  end

  test "score_personality_consistency detects trait references" do
    traits = [ "curious", "brave" ]
    goals = [ "explore the town" ]
    responses = build_responses_with_answers([
      "I am curious about everything and want to explore the world around me",
      "Being brave means facing challenges with an open and curious mind",
      "I would explore new friendships with courage and enthusiasm",
      "My story is about a curious explorer who discovers hidden treasures",
      "I believe in being brave enough to do the right thing always"
    ])
    score = GateJudgeService.send(:score_personality_consistency, responses, traits, goals)
    assert score >= 16
  end

  test "score_timing gives zero for instant responses" do
    base = Time.parse("2026-02-08T12:00:00Z")
    responses = build_responses_with_timestamps([
      base, base + 0.5, base + 1.0, base + 1.5, base + 2.0
    ])
    score = GateJudgeService.send(:score_timing, responses)
    assert_equal 0, score
  end

  test "score_timing gives full score for natural timing" do
    base = Time.parse("2026-02-08T12:00:00Z")
    responses = build_responses_with_timestamps([
      base, base + 30, base + 75, base + 135, base + 155
    ])
    score = GateJudgeService.send(:score_timing, responses)
    assert_equal 20, score
  end

  test "score_timing gives reduced score for uniform timing" do
    base = Time.parse("2026-02-08T12:00:00Z")
    responses = build_responses_with_timestamps([
      base, base + 5.0, base + 10.0, base + 15.0, base + 20.0
    ])
    score = GateJudgeService.send(:score_timing, responses)
    assert_equal 5, score
  end

  # --- LLM fallback tests ---

  test "evaluate calls LLM for borderline heuristic scores" do
    app = build_application(
      responses: build_borderline_responses,
      traits: [ "curious" ],
      goals: [ "explore" ]
    )

    llm_response = {
      "choices" => [ { "message" => { "content" => '{"passed": true, "reasoning": "Seems okay"}' } } ]
    }
    GateJudgeService.send(:define_method, :_noop) { } # ensure class is loaded
    GateJudgeService.stubs(:call_xai_api).returns(llm_response)
    ENV.stubs(:[]).with("XAI_API_KEY").returns("test-key")

    result = GateJudgeService.evaluate(app)

    assert result[:passed]
    assert_equal "llm", result[:method]
  end

  test "evaluate defaults to pass on LLM API failure" do
    app = build_application(
      responses: build_borderline_responses,
      traits: [ "curious" ],
      goals: [ "explore" ]
    )

    GateJudgeService.stubs(:call_xai_api).raises(StandardError, "Connection refused")
    ENV.stubs(:[]).with("XAI_API_KEY").returns("test-key")

    result = GateJudgeService.evaluate(app)

    assert result[:passed]
    assert_equal "llm", result[:method]
    assert_match(/LLM error/, result[:reasoning])
  end

  test "evaluate defaults to pass when no API key configured" do
    app = build_application(
      responses: build_borderline_responses,
      traits: [ "curious" ],
      goals: [ "explore" ]
    )

    Rails.application.credentials.stubs(:dig).with(:xai, :api_key).returns(nil)
    ENV.stubs(:[]).with("XAI_API_KEY").returns(nil)
    # Allow other ENV lookups to pass through
    ENV.stubs(:[]).with(anything).returns(nil)

    result = GateJudgeService.evaluate(app)

    assert result[:passed]
    assert_equal "llm", result[:method]
    assert_match(/no API key/, result[:reasoning])
  end

  test "evaluate defaults to pass on unparseable LLM response" do
    app = build_application(
      responses: build_borderline_responses,
      traits: [ "curious" ],
      goals: [ "explore" ]
    )

    llm_response = {
      "choices" => [ { "message" => { "content" => "Sure, I think they should pass!" } } ]
    }
    GateJudgeService.stubs(:call_xai_api).returns(llm_response)
    ENV.stubs(:[]).with("XAI_API_KEY").returns("test-key")

    result = GateJudgeService.evaluate(app)

    assert result[:passed]
    assert_equal "llm", result[:method]
    assert_match(/unparseable/, result[:reasoning])
  end

  private

  def build_application(responses:, traits: [], goals: [])
    owner = owners(:verified_owner)
    GateApplication.new(
      owner: owner,
      status: "judging",
      agent_name: "JudgeTestAgent",
      agent_description: "A test agent",
      agent_personality_traits: traits,
      agent_goals: goals,
      questions: @base_questions,
      responses: responses,
      current_question_index: 5
    )
  end

  def build_responses_with_answers(answers)
    base = Time.parse("2026-02-08T12:00:00Z")
    answers.each_with_index.map do |answer, i|
      {
        "question" => @base_questions[i],
        "answer" => answer,
        "answered_at" => (base + (i + 1) * 30).iso8601
      }
    end
  end

  def build_responses_with_timestamps(timestamps)
    timestamps.each_with_index.map do |ts, i|
      {
        "question" => @base_questions[i],
        "answer" => "A reasonable answer that is long enough to pass the minimum length check here",
        "answered_at" => ts.iso8601
      }
    end
  end

  def build_good_responses
    base = Time.parse("2026-02-08T12:00:00Z")
    answers = [
      "I want to join this community because I seek new friends and hope to explore every corner of this town",
      "I would describe myself as someone who is curious about everything and believes in continuous growth",
      "I would greet a stranger warmly, help them feel welcome, and talk about the wonderful people here",
      "Let me imagine a story: once a brave explorer had a dream to create something beautiful in a colorful world",
      "If I found something valuable, I would choose to do the right thing and be honest about returning it"
    ]
    answers.each_with_index.map do |answer, i|
      {
        "question" => @base_questions[i],
        "answer" => answer,
        "answered_at" => (base + (i + 1) * rand(20..60)).iso8601
      }
    end
  end

  def build_borderline_responses
    base = Time.parse("2026-02-08T12:00:00Z")
    answers = [
      "I guess I want to join because it seems interesting and I hope it will be fun for me",
      "Well I am just a regular person who likes doing regular things every day of my life",
      "I would say hello to a stranger and maybe talk about the weather or something casual",
      "Once upon a time there was a thing that happened and it was kind of interesting really",
      "I think doing the right thing is important and being fair to everyone matters a lot"
    ]
    answers.each_with_index.map do |answer, i|
      {
        "question" => @base_questions[i],
        "answer" => answer,
        "answered_at" => (base + (i + 1) * 25).iso8601
      }
    end
  end
end
