class CreateVouchers < ActiveRecord::Migration[8.1]
  def change
    create_table :vouchers do |t|
      t.string :kind, null: false, default: "receipt"
      t.date :issued_on
      t.text :description, null: false, default: ""
      t.integer :amount
      t.string :status, null: false, default: "pending"
      t.text :notes, null: false, default: ""
      t.text :ai_questions, null: false, default: ""
      t.string :ai_error
      t.timestamps
    end
    add_index :vouchers, :status
  end
end
