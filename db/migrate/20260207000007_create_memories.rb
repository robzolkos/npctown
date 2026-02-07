class CreateMemories < ActiveRecord::Migration[8.1]
  def change
    create_table :memories, id: :string, limit: 32 do |t|
      t.string :agent_id, limit: 32, null: false
      t.string :memory_type, null: false
      t.text :content, null: false
      t.integer :importance, null: false, default: 5
      t.integer :tick, null: false
      t.jsonb :related_agent_ids, null: false, default: []
      t.string :location_id, limit: 32

      t.timestamps
    end

    add_index :memories, [ :agent_id, :tick ]
    add_index :memories, [ :agent_id, :memory_type ]
    add_index :memories, :importance
    add_index :memories, :memory_type
    add_foreign_key :memories, :agents, column: :agent_id
    add_foreign_key :memories, :locations, column: :location_id
  end
end
