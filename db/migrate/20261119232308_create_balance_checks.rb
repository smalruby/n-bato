class CreateBalanceChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :balance_checks do |t|
      t.references :account, null: false, foreign_key: true
      t.date :checked_on
      t.integer :actual_amount
      t.string :note

      t.timestamps
    end
  end
end
