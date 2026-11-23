# 会員・役員になる人。住所・メール・電話は暗号化して保存する。
class Person < ApplicationRecord
  include YearRecords
  encrypts :address, :email, :phone
  year_records :person_years, %i[name name_kana address email phone notes]

  has_many :memberships, dependent: :destroy
  has_many :officer_terms, dependent: :restrict_with_error

  validates :name, presence: true
  scope :ordered, -> { order(:name_kana, :name) }

  def to_s = name
  def member_in?(year, kind: "regular") = memberships.any? { it.fiscal_year == year && it.kind == kind }
end
