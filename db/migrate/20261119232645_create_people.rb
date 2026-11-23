class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.string :name, null: false
      t.string :name_kana, null: false, default: ""
      t.text :address # 暗号化
      t.text :email # 暗号化
      t.text :phone # 暗号化
      t.text :notes, null: false, default: ""
      t.timestamps
    end
  end
end
