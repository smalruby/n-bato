class AddRoleAndUiPrefsToUsers < ActiveRecord::Migration[8.1]
  def change
    # 役割: clerk(事務。すべての操作) / auditor(監査。閲覧だけ)
    add_column :users, :role, :string, null: false, default: "clerk"
    # 画面ごとの表示の好み(説明を畳んだか など)
    add_column :users, :ui_prefs, :json, null: false, default: {}
  end
end
