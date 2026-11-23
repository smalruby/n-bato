# 通帳や手元現金の実際の残高と、帳簿の残高を照らし合わせた記録。
class BalanceCheck < ApplicationRecord
  belongs_to :account
  validates :checked_on, presence: true
  validates :actual_amount, numericality: { only_integer: true }
  validate { errors.add(:account, "は資産の科目にしてください") if account && account.category != "asset" }

  scope :recent, -> { order(checked_on: :desc, id: :desc) }

  def book_amount(book = Ledger::Book.new) = book.balance_as_of(account, checked_on)
  def difference(book = Ledger::Book.new) = actual_amount - book_amount(book)
end
