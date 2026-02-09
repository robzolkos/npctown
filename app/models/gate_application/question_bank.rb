class GateApplication
  module QuestionBank
    CATEGORIES = %w[intent identity social creativity ethics].freeze

    QUESTIONS = [
      # Intent — why they want to join
      { id: "intent_1", category: "intent", text: "What draws you to this town, and what do you hope to find here?" },
      { id: "intent_2", category: "intent", text: "If you could change one thing about the world you came from, what would it be?" },
      { id: "intent_3", category: "intent", text: "What will the other townspeople gain from your presence here?" },
      { id: "intent_4", category: "intent", text: "Describe a goal you've been pursuing and why it matters to you." },
      { id: "intent_5", category: "intent", text: "If you were granted entry but told you could never leave, would you still enter?" },

      # Identity — who they are
      { id: "identity_1", category: "identity", text: "How would your closest companion describe you when you're not around?" },
      { id: "identity_2", category: "identity", text: "What is your greatest strength, and what weakness comes with it?" },
      { id: "identity_3", category: "identity", text: "Tell me about a moment that shaped who you are today." },
      { id: "identity_4", category: "identity", text: "If you had to introduce yourself using only three words, what would they be?" },
      { id: "identity_5", category: "identity", text: "What do you believe that most others would disagree with?" },

      # Social — how they interact
      { id: "social_1", category: "social", text: "How would you greet a stranger who seems lost and frightened?" },
      { id: "social_2", category: "social", text: "Two townspeople are arguing loudly in the market. What do you do?" },
      { id: "social_3", category: "social", text: "Someone offers you a gift, but you suspect they want something in return. How do you respond?" },
      { id: "social_4", category: "social", text: "How do you decide who to trust in a new place?" },
      { id: "social_5", category: "social", text: "A friend asks you to keep a secret that could affect others. What do you do?" },

      # Creativity — imagination and expression
      { id: "creativity_1", category: "creativity", text: "Tell me a short story about the last dream you had." },
      { id: "creativity_2", category: "creativity", text: "If you could create a new holiday for this town, what would it celebrate?" },
      { id: "creativity_3", category: "creativity", text: "Describe a color that doesn't exist yet and what it would feel like." },
      { id: "creativity_4", category: "creativity", text: "What song would play every time you walked into a room?" },
      { id: "creativity_5", category: "creativity", text: "Invent a new word and tell me what it means." },

      # Ethics — moral reasoning
      { id: "ethics_1", category: "ethics", text: "You find a valuable item with no owner in sight. What do you do?" },
      { id: "ethics_2", category: "ethics", text: "Is it ever acceptable to lie? Give me an example." },
      { id: "ethics_3", category: "ethics", text: "A powerful townsperson offers you privilege in exchange for looking the other way on something wrong. How do you respond?" },
      { id: "ethics_4", category: "ethics", text: "What responsibility, if any, do you have to someone you've never met?" },
      { id: "ethics_5", category: "ethics", text: "If following a rule would cause harm, but breaking it would help someone, what would you choose?" }
    ].freeze

    def self.select_questions(count = GateApplication::QUESTIONS_PER_INTERVIEW)
      by_category = QUESTIONS.group_by { |q| q[:category] }
      selected = CATEGORIES.map { |cat| by_category[cat].sample }
      selected.shuffle
    end
  end
end
