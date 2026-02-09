class AddOwnerToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :owner_id, :string, limit: 32
    add_column :agents, :probation_until, :datetime
    add_index :agents, :owner_id
  end
end
