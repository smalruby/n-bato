class AddPhoneAndSettingsToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :phone, :string
    add_column :organizations, :settings, :json
  end
end
