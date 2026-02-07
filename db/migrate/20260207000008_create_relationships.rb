class CreateRelationships < ActiveRecord::Migration[8.1]
  def change
    create_table :relationships, id: :string, limit: 32 do |t|
      t.string :agent_id, limit: 32, null: false
      t.string :target_agent_id, limit: 32, null: false
      t.integer :trust, null: false, default: 0
      t.integer :affection, null: false, default: 0
      t.integer :respect, null: false, default: 0
      t.integer :familiarity, null: false, default: 0
      t.integer :last_interaction_tick

      t.timestamps
    end

    add_index :relationships, [ :agent_id, :target_agent_id ], unique: true
    add_index :relationships, :target_agent_id
    add_foreign_key :relationships, :agents, column: :agent_id
    add_foreign_key :relationships, :agents, column: :target_agent_id
  end
end
