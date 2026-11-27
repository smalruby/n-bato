# 年度ごとの会員資格(定款の会員種別)。正会員が NPO 法上の社員。
class Membership < ApplicationRecord
  KINDS = {"regular" => "正会員", "active" => "活動会員", "student" => "受講会員", "supporting" => "賛助会員",
           "supporting_group" => "賛助会員（団体）", "volunteer" => "ボランティア会員"}.freeze

  belongs_to :person
  # 会費の納入はイベント(Membership::FeePayment.record!)。納めた記録のある会員資格は消せない
  has_one :fee_payment, class_name: "Membership::FeePayment", dependent: :restrict_with_error
  validates :fiscal_year, presence: true
  validates :kind, inclusion: {in: KINDS.keys}
  validates :person_id, uniqueness: {scope: %i[fiscal_year kind]}

  scope :regular, -> { where(kind: "regular") }
  scope :in_fiscal_year, ->(year) { where(fiscal_year: year) }

  def kind_label = KINDS[kind]
  def fee_paid? = fee_payment.present?
end
