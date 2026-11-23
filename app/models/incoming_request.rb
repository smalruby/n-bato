# 外から届いた依頼(松江市のメールなど)。やることは、依頼ごとの AI との対話で作る(デザインシステム「やること」)。
class IncomingRequest < ApplicationRecord
  STATUSES = { "open" => "進行中", "resolved" => "解決" }.freeze

  has_many :todos, -> { order(:position, :id) }, dependent: :destroy
  has_many :messages, -> { order(:id) }, class_name: "IncomingRequestMessage", dependent: :destroy

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES.keys }

  scope :ordered, -> { order(Arel.sql("status = 'resolved', due_on IS NULL, due_on, id")) }

  def status_label = STATUSES.fetch(status)
  def resolved? = status == "resolved"
  def all_done? = todos.any? && todos.all?(&:done?)
  def done_count = todos.count(&:done?)
  def audit_fiscal_year = nil
end
