# 会費を納めた(イベント。日付は paid_on)。1 つの会員資格(1 人の 1 年度)に 1 回。docs/adr/0030
# 元に戻せない操作。いまは記録する画面が無く、data:load や運用のスクリプトから記録する(画面は見直し票で決めてから)。
class Membership::FeePayment < ApplicationRecord
  include EventRecord

  event_of :paid_on, entry: :record!

  belongs_to :membership
  belongs_to :recorder, class_name: "User", optional: true

  validates :amount, numericality: {only_integer: true, greater_than_or_equal_to: 0}
  validates :paid_on, presence: true

  def audit_fiscal_year = membership&.fiscal_year

  # 記録する(作る入口)。by: は人が画面から記録するときに渡す(rake・AI からは省ける)。
  def self.record!(membership, amount:, paid_on:, by: nil)
    paid_on = ActiveModel::Type::Date.new.cast(paid_on)
    raise ArgumentError, "会費を納めた日を入れてください" unless paid_on
    amount = Integer(amount.to_s, exception: false)
    raise ArgumentError, "会費の金額は 0 円以上の整数で入れてください" unless amount && amount >= 0
    raise ArgumentError, "この会員資格の会費は、もう納めた記録があります" if exists?(membership:)

    transaction do
      payment = create!(membership:, amount:, paid_on:, recorder: by)
      membership.reset_fee_payment
      Audit.final!("#{membership.person.name}さんの#{membership.fiscal_year}年度の会費の納入を記録した")
      payment
    end
  end
end
