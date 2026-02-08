class AddReflectedUponToMemories < ActiveRecord::Migration[8.1]
  def change
    add_column :memories, :reflected_upon, :boolean, null: false, default: false
    add_index :memories, [ :agent_id, :reflected_upon ],
              where: "reflected_upon = FALSE AND memory_type = 'observation'",
              name: "idx_memories_unreflected_observations"
  end
end
