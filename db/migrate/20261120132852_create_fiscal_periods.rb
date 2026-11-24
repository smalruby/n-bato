# 年度の状態(デザインシステム「年度」)。締めたかどうかを記録する。仮(前の年度を締める前の次の年度)は前の年度の状態から決まる。
class CreateFiscalPeriods < ActiveRecord::Migration[8.1]
  def change
    create_table :fiscal_periods do |t|
      t.integer :year, null: false
      t.date :closed_on
      t.references :closed_by, foreign_key: {to_table: :users}
      t.text :note
      t.timestamps
    end
    add_index :fiscal_periods, :year, unique: true
  end
end
