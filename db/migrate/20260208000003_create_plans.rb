class CreatePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :plans, id: { type: :string, limit: 32 } do |t|
      t.string :agent_id, limit: 32, null: false
      t.text :goal, null: false
      t.jsonb :steps, default: [], null: false
      t.string :status, null: false, default: "active"
      t.integer :created_at_tick, null: false
      t.integer :last_updated_at_tick, null: false

      t.timestamps
    end

    add_index :plans, [ :agent_id, :status ]
    add_index :plans, :status
    add_index :plans, :last_updated_at_tick
    add_foreign_key :plans, :agents, column: :agent_id
  end
end
