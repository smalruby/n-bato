class AddWorkingYearToUsersAndReasonToAuditOperations < ActiveRecord::Migration[8.1]
  def change
    # 操作する年度(人ごとに覚える)
    add_column :users, :working_year, :integer
    # 締めた年度を直したときの理由(変更の記録に残す)
    add_column :audit_operations, :reason, :text
  end
end
