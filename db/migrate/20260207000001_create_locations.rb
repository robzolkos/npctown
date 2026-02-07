class CreateLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :locations, id: :string, limit: 32 do |t|
      t.string :name, null: false
      t.text :description
      t.string :location_type, null: false

      t.timestamps
    end

    add_index :locations, :name, unique: true
    add_index :locations, :location_type
  end
end
