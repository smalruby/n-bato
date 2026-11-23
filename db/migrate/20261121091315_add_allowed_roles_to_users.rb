# 切り替えられる役割(デザインシステム「役割」)。role はいま使っている役割。
# 事務の利用者(理事長)は事務・監査の両方、監査の利用者は監査だけにしておく。
class AddAllowedRolesToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :allowed_roles, :string, null: false, default: "clerk"
    execute "UPDATE users SET allowed_roles = 'clerk,auditor' WHERE role = 'clerk'"
    execute "UPDATE users SET allowed_roles = 'auditor' WHERE role = 'auditor'"
  end

  def down
    remove_column :users, :allowed_roles
  end
end
