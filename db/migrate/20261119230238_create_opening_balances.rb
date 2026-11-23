class CreateOpeningBalances < ActiveRecord::Migration[8.0]
  def change
    create_table :opening_balances do |t|
      t.integer :fiscal_year, null: false
      t.references :account, null: false, foreign_key: true
      t.integer :amount, null: false, default: 0
      t.timestamps
    end
    add_index :opening_balances, [ :fiscal_year, :account_id ], unique: true
  end
end
