# 証憑(領収書・レシート・通帳の写し・メモなど)。AI がこれを読んで仕訳を提案する。
class Voucher < ApplicationRecord
  KINDS = { "receipt" => "領収書・レシート", "bank" => "通帳・入出金明細", "invoice" => "請求書", "memo" => "メモ（証憑なし）" }.freeze
  STATUSES = { "pending" => "未処理", "proposing" => "AI が作業中", "proposed" => "提案あり（要確認）",
               "booked" => "記帳済み", "error" => "AI エラー", "rejected" => "記帳しない" }.freeze
  ACCEPTED_TYPES = %w[image/jpeg image/png image/gif image/webp application/pdf].freeze

  has_many_attached :files
  has_many :journal_proposals, dependent: :destroy

  validates :kind, inclusion: { in: KINDS.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validate :files_must_be_supported
  validate { errors.add(:base, "ファイルか説明のどちらかを入れてください") if description.blank? && !files.attached? }

  scope :recent, -> { order(created_at: :desc) }

  def kind_label = KINDS[kind]
  def status_label = STATUSES[status]
  def open_proposals = journal_proposals.where(status: "proposed")

  def refresh_status!
    return if status.in?(%w[proposing error rejected])

    new_status = if journal_proposals.where(status: "proposed").exists? then "proposed"
    elsif journal_proposals.where(status: "approved").exists? then "booked"
    else "pending"
    end
    update!(status: new_status)
  end

  private

  def files_must_be_supported
    files.each do |file|
      errors.add(:files, "は画像（JPEG・PNG など）か PDF にしてください") unless ACCEPTED_TYPES.include?(file.content_type)
    end
  end
end
