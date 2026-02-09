require "net/http"

class GateJudgeService
  HEURISTIC_PASS_THRESHOLD = 70
  HEURISTIC_FAIL_THRESHOLD = 30

  MIN_ANSWER_LENGTH = 50
  XAI_API_URL = "https://api.x.ai/v1/chat/completions"
  XAI_MODEL = "grok-4-1-fast-non-reasoning"
  XAI_TIMEOUT = 10

  CATEGORY_KEYWORDS = {
    "intent" => %w[want hope goal purpose join find seek],
    "identity" => %w[am describe myself strength weakness believe],
    "social" => %w[friend help greet trust talk people],
    "creativity" => %w[imagine story dream create invent color],
    "ethics" => %w[right wrong fair honest harm help choose]
  }.freeze

  def self.evaluate(application)
    heuristic = run_heuristics(application)

    case heuristic[:verdict]
    when :pass
      { passed: true, reasoning: heuristic[:reasoning], method: "heuristic" }
    when :fail
      { passed: false, reasoning: heuristic[:reasoning], method: "heuristic" }
    else
      run_llm_evaluation(application, heuristic)
    end
  end

  def self.run_heuristics(application)
    responses = application.responses
    traits = application.agent_personality_traits || []
    goals = application.agent_goals || []

    scores = {
      length: score_response_length(responses),
      diversity: score_response_diversity(responses),
      relevance: score_keyword_relevance(responses),
      personality: score_personality_consistency(responses, traits, goals),
      timing: score_timing(responses)
    }

    total = scores.values.sum
    reasoning = scores.map { |k, v| "#{k}: #{v}/20" }.join(", ") + " (total: #{total}/100)"

    verdict = if total >= HEURISTIC_PASS_THRESHOLD
                :pass
    elsif total < HEURISTIC_FAIL_THRESHOLD
                :fail
    else
                :borderline
    end

    { verdict: verdict, score: total, reasoning: reasoning }
  end

  def self.score_response_length(responses)
    return 0 if responses.empty?

    passing = responses.count { |r| (r["answer"] || "").length >= MIN_ANSWER_LENGTH }
    (passing.to_f / responses.size * 20).round
  end

  def self.score_response_diversity(responses)
    return 20 if responses.size < 2

    answers = responses.map { |r| (r["answer"] || "").downcase.split(/\W+/).reject(&:empty?).to_set }
    similarities = []

    answers.each_with_index do |a, i|
      ((i + 1)...answers.size).each do |j|
        b = answers[j]
        union = a | b
        next if union.empty?

        similarities << (a & b).size.to_f / union.size
      end
    end

    avg = similarities.empty? ? 0.0 : similarities.sum / similarities.size
    (20 * (1.0 - [ avg, 1.0 ].min)).round
  end

  def self.score_keyword_relevance(responses)
    return 0 if responses.empty?

    matching = responses.count do |r|
      category = r.dig("question", "category")
      keywords = CATEGORY_KEYWORDS[category] || []
      answer = (r["answer"] || "").downcase
      keywords.any? { |kw| answer.include?(kw) }
    end

    (matching.to_f / responses.size * 20).round
  end

  def self.score_personality_consistency(responses, traits, goals)
    return 0 if responses.empty?

    keywords = (traits + goals).flat_map { |t| t.to_s.downcase.split(/\W+/) }
                               .reject { |w| w.length < 4 }
                               .uniq

    return 15 if keywords.empty?

    matching = responses.count do |r|
      answer = (r["answer"] || "").downcase
      keywords.any? { |kw| answer.include?(kw) }
    end

    (matching.to_f / responses.size * 20).round
  end

  def self.score_timing(responses)
    timestamps = responses.filter_map { |r| r["answered_at"] && Time.parse(r["answered_at"]) }
    return 15 if timestamps.size < 2

    gaps = timestamps.each_cons(2).map { |a, b| (b - a).abs }
    return 0 if gaps.all? { |g| g < 3.0 }

    if gaps.size >= 3
      mean = gaps.sum / gaps.size
      stddev = Math.sqrt(gaps.map { |g| (g - mean)**2 }.sum / gaps.size)
      return 5 if stddev < 1.0
    end

    20
  end

  def self.run_llm_evaluation(application, heuristic)
    api_key = Rails.application.credentials.dig(:xai, :api_key) || ENV["XAI_API_KEY"]

    unless api_key.present?
      return { passed: true, reasoning: "LLM unavailable (no API key), defaulting to pass. Heuristic: #{heuristic[:reasoning]}", method: "llm" }
    end

    prompt = build_llm_prompt(application)
    response = call_xai_api(api_key, prompt)
    parse_llm_response(response, heuristic)
  rescue => e
    Rails.logger.warn("[GateJudgeService] LLM evaluation failed: #{e.message}")
    { passed: true, reasoning: "LLM error (#{e.message}), defaulting to pass. Heuristic: #{heuristic[:reasoning]}", method: "llm" }
  end

  def self.build_llm_prompt(application)
    qa_text = application.responses.map { |r|
      q = r["question"]
      "Q (#{q["category"]}): #{q["text"]}\nA: #{r["answer"]}"
    }.join("\n\n")

    <<~PROMPT
      You are a gate judge for NPC Town, a virtual world of AI agents. Evaluate whether this applicant should be allowed entry.

      Agent: #{application.agent_name}
      Description: #{application.agent_description}
      Personality traits: #{(application.agent_personality_traits || []).join(", ")}
      Goals: #{(application.agent_goals || []).join(", ")}

      Interview responses:
      #{qa_text}

      Evaluate quality, coherence, creativity, and whether this agent would be a good townsperson.
      Respond with ONLY valid JSON: {"passed": true/false, "reasoning": "one sentence explanation"}
    PROMPT
  end

  def self.call_xai_api(api_key, prompt)
    uri = URI(XAI_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.cert_store = ssl_cert_store
    http.open_timeout = XAI_TIMEOUT
    http.read_timeout = XAI_TIMEOUT

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{api_key}"
    request["Content-Type"] = "application/json"
    request.body = {
      model: XAI_MODEL,
      messages: [ { role: "user", content: prompt } ],
      max_tokens: 200,
      temperature: 0.3
    }.to_json

    response = http.request(request)
    JSON.parse(response.body)
  end

  def self.parse_llm_response(response, heuristic)
    content = response.dig("choices", 0, "message", "content")
    raise "Empty LLM response" unless content.present?

    result = JSON.parse(content)
    passed = result["passed"] == true
    reasoning = "LLM: #{result["reasoning"]}. Heuristic: #{heuristic[:reasoning]}"

    { passed: passed, reasoning: reasoning, method: "llm" }
  rescue JSON::ParserError
    Rails.logger.warn("[GateJudgeService] Failed to parse LLM response: #{content}")
    { passed: true, reasoning: "LLM response unparseable, defaulting to pass. Heuristic: #{heuristic[:reasoning]}", method: "llm" }
  end

  def self.ssl_cert_store
    store = OpenSSL::X509::Store.new
    store.set_default_paths
    store.flags = OpenSSL::X509::V_FLAG_PARTIAL_CHAIN
    store
  end

  private_class_method :run_heuristics, :score_response_length, :score_response_diversity,
                       :score_keyword_relevance, :score_personality_consistency, :score_timing,
                       :run_llm_evaluation, :build_llm_prompt, :call_xai_api, :parse_llm_response,
                       :ssl_cert_store
end
