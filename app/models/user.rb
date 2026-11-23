class User < ApplicationRecord
  self.audited = false
  ROLES = { "clerk" => "事務", "auditor" => "監査" }.freeze
  validates :role, inclusion: { in: ROLES.keys }
  validate :role_must_be_allowed

  # role はいま使っている役割、allowed_roles は切り替えられる役割(デザインシステム「役割」)
  def auditor? = role == "auditor"
  def role_label = ROLES.fetch(role)
  def roles = allowed_roles.to_s.split(",") & ROLES.keys
  def roles=(list)
    self.allowed_roles = (Array(list).map(&:to_s) & ROLES.keys).join(",")
  end
  def can_use?(r) = roles.include?(r.to_s)

  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  private

  def role_must_be_allowed
    errors.add(:role, "は切り替えられる役割にありません") unless can_use?(role)
  end
end
