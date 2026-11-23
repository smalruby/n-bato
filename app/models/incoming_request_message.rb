# 依頼ごとの対話の 1 件。人の発言は、伏せた文(masked_body)だけを AI に送る。添付は送るかを人が選ぶ(既定は送らない)。
class IncomingRequestMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :incoming_request
  has_many_attached :files

  validates :role, inclusion: { in: ROLES }

  def user? = role == "user"
  def sent? = sent_at.present?
  def applied? = applied_at.present?
  def proposal_todos = Array(proposal&.dig("todos_new"))
  def proposal_updates = Array(proposal&.dig("todos_update"))
  def proposal_actionable? = !user? && !applied? && (proposal_todos.any? || proposal_updates.any? || proposal&.dig("request", "title").present?)
  def audit_fiscal_year = nil
end
