# 登記の申請(見直し第20回、docs/adr/0031)。
# - 登記(registrations)は「登記の事由」(重任・就任・住所の変更・氏の変更)1 つ。どの申請に入れたかと、登記した日(いまの状態)を持つ。
# - 登記の申請(registration_filings)は長いイベント。申請した・受付・補正・完了・取下げは詳細のイベント。
class CreateRegistrationFilings < ActiveRecord::Migration[8.1]
  def change
    create_table :registration_filings do |t|
      t.string :status, null: false, default: "drafting"
      t.text :note, null: false, default: ""
      t.references :general_meeting_resolution, foreign_key: {to_table: :resolutions}
      t.references :board_resolution, foreign_key: {to_table: :resolutions}
      t.timestamps
    end
    create_table :registration_filing_submissions do |t|
      t.references :registration_filing, null: false, foreign_key: true, index: {unique: true}
      t.string :application_number, null: false, default: ""
      t.references :recorded_by, foreign_key: {to_table: :users}
      t.date :submitted_on, null: false
    end
    create_table :registration_filing_acceptances do |t|
      t.references :registration_filing, null: false, foreign_key: true, index: {unique: true}
      t.string :receipt_number, null: false, default: ""
      t.references :recorded_by, foreign_key: {to_table: :users}
      t.date :accepted_on, null: false
    end
    create_table :registration_filing_corrections do |t|
      t.references :registration_filing, null: false, foreign_key: true
      t.text :note, null: false
      t.references :recorded_by, foreign_key: {to_table: :users}
      t.date :noticed_on, null: false
    end
    create_table :registration_filing_completions do |t|
      t.references :registration_filing, null: false, foreign_key: true, index: {unique: true}
      t.references :recorded_by, foreign_key: {to_table: :users}
      t.date :completed_on, null: false
    end
    create_table :registration_filing_withdrawals do |t|
      t.references :registration_filing, null: false, foreign_key: true, index: {unique: true}
      t.text :reason, null: false
      t.references :recorded_by, foreign_key: {to_table: :users}
      t.date :withdrawn_on, null: false
    end

    add_reference :registrations, :registration_filing, foreign_key: true
    add_reference :registrations, :person_address_change, foreign_key: true
    add_reference :registrations, :person_name_change, foreign_key: true
    change_column_null :registrations, :due_on, true

    # やること: 待ちが解ける決まり(例: 登記が完了したら「作業中」に戻す)
    add_column :todos, :resume_rule, :string, null: false, default: ""
  end
end
