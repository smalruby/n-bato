# 入会申込(デザインシステム「入会申込」)。申込はまだ会員ではない。理事長が認めたときに人と会員資格を作る(定款第7条)。
class CreateMemberApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :member_applications do |t|
      t.date :applied_on, null: false
      t.string :name, null: false
      t.string :name_kana, null: false, default: ""
      t.string :age_group, null: false, default: ""
      t.text :postal_code
      t.text :address
      t.text :email
      t.text :phone
      t.string :notice_method, null: false, default: ""
      t.string :materials_method, null: false, default: ""
      t.text :referral
      t.text :help_offers
      t.text :comments
      t.string :source, null: false, default: "google_form"
      t.string :source_key
      t.string :status, null: false, default: "received"
      t.integer :fiscal_year
      t.date :joined_on
      t.date :decided_on
      t.text :reason
      t.references :person, foreign_key: true
      t.timestamps
    end
    add_index :member_applications, :source_key, unique: true
  end
end
