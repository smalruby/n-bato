# 年度初めの残高(貸借対照表科目)。仕訳データより前の年度の繰越額を与えるのに使う。
# 資産は借方、負債・正味財産は貸方をプラスで持つ。
class OpeningBalance < ApplicationRecord
  belongs_to :account
  validates :fiscal_year, presence: true, uniqueness: {scope: :account_id}
  validates :amount, numericality: {only_integer: true}
  validate { errors.add(:account, "は貸借対照表の科目にしてください") if account && !account.balance_sheet? }
end
