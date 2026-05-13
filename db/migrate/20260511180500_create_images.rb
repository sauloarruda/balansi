class CreateImages < ActiveRecord::Migration[8.1]
  def change
    create_table :images do |t|
      t.references :recipe, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :images, [ :recipe_id, :position ], name: "images_recipe_position_idx"
  end
end
