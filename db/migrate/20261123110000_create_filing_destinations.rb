# 提出先(所轄庁などの窓口。見直し第17回、docs/adr/0027)。年度に依存しないリソースと、確かめた出来事、AI の調べもの(長いイベント)。
class CreateFilingDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :filing_destinations do |t|
      t.string :kind, null: false                 # authority / prefectural_tax / municipal_tax / registry / tax_office / other
      t.string :name, null: false, default: ""    # 機関の名前(例: 松江市)
      t.string :addressee, null: false, default: "" # 書類の宛先(役職と氏名)
      t.string :office, null: false, default: ""  # 窓口(課・係)
      t.string :address, null: false, default: ""
      t.string :phone, null: false, default: ""
      t.string :fax, null: false, default: ""
      t.string :email, null: false, default: ""
      t.string :hours, null: false, default: ""
      t.string :forms_url, null: false, default: ""
      t.text :source, null: false, default: ""    # 出どころ(URL や文書)
      t.text :notes, null: false, default: ""
      t.string :origin, null: false, default: "human" # human / ai
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :filing_destinations, :kind

    create_table :filing_destination_confirmations do |t|
      t.references :filing_destination, null: false, foreign_key: true
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.string :digest, null: false               # 確かめた中身の要約(中身が変わったら確認済みでなくなる)
      t.datetime :confirmed_at, null: false
    end

    create_table :filing_destination_searches do |t|
      t.string :address, null: false, default: ""
      t.string :status, null: false, default: "searching" # searching / done / failed(長いイベントのいまの状態)
      t.text :error_message, null: false, default: ""
      t.integer :found_count, null: false, default: 0
      t.references :requested_by, foreign_key: { to_table: :users }
      t.datetime :requested_at, null: false
    end
  end
end
