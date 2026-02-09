class CreateGateApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :gate_applications, id: :string, limit: 32 do |t|
      t.string :owner_id, limit: 32, null: false
      t.string :agent_id, limit: 32
      t.string :status, null: false, default: "pending"
      t.string :agent_name, null: false
      t.text :agent_description
      t.jsonb :agent_personality_traits, default: [], null: false
      t.jsonb :agent_goals, default: [], null: false
      t.jsonb :questions, default: [], null: false
      t.jsonb :responses, default: [], null: false
      t.integer :current_question_index, default: 0
      t.text :judge_reasoning
      t.datetime :expires_at

      t.timestamps
    end

    add_index :gate_applications, :owner_id
    add_index :gate_applications, :status
    add_index :gate_applications, [ :owner_id, :status ]
    add_foreign_key :gate_applications, :owners, column: :owner_id
  end
end
