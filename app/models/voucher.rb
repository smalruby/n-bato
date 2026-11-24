# 証憑(領収書・レシート・通帳の写し・メモなど)。AI がこれを読んで仕訳を提案する。
class Voucher < ApplicationRecord
  KINDS = {"receipt" => "領収書・レシート", "bank" => "通帳・入出金明細", "invoice" => "請求書", "memo" => "メモ（証憑なし）"}.freeze
  STATUSES = {"pending" => "未処理", "proposing" => "AI が作業中", "proposed" => "提案あり（要確認）",
              "booked" => "記帳済み", "error" => "AI エラー", "rejected" => "記帳しない"}.freeze
  ACCEPTED_TYPES = %w[image/jpeg image/png image/gif image/webp application/pdf].freeze

  has_many_attached :files
  has_many :journal_proposals, dependent: :restrict_with_error # 提案はイベントなので消さない

  validates :kind, inclusion: {in: KINDS.keys}
  validates :status, inclusion: {in: STATUSES.keys}
  validate :files_must_be_supported
  validate { errors.add(:base, "ファイルか説明のどちらかを入れてください") if description.blank? && !files.attached? }

  scope :recent, -> { order(created_at: :desc) }

  def kind_label = KINDS[kind]
  def status_label = STATUSES[status]
  def open_proposals = journal_proposals.pending

  # 消せないときの理由(BlockedReason)。消せるなら nil。証憑の画面と、消そうとして断るときの文で使う。
  def destroy_blocked_reason
    return unless (count = journal_proposals.count).positive?

    BlockedReason.new(title: "この証憑は消せません", reason: "AI の提案は記録として残すので、提案のある証憑は消せません。",
                      what: "AI の仕訳の提案が #{count} 件あります", link_label: "提案を見る", link_target: "#proposals",
                      alternative: ("代わりに: 記帳しないときは「記帳しない」を押してください。" unless status.in?(%w[booked rejected])))
  end

  # 証憑は長いイベント(docs/data-model.md)。いまの状態(status)を書き換えてよいのは、詳細のイベントの作る入口だけ。
  # AI の作業中・エラー・記帳しない は、提案のイベントからは決まらない状態なので、そのまま残す。
  MANUAL_STATUSES = %w[proposing error rejected].freeze

  # 提案のイベント(承認・却下・取り下げ)と仕訳の取消から決まる、いまの状態(取り消した仕訳の承認は「記帳済み」に数えない)
  def derived_status
    return status if status.in?(MANUAL_STATUSES)

    if journal_proposals.pending.exists? then "proposed"
    elsif journal_proposals.approved.joins(:journal_entry).merge(JournalEntry.active).exists? then "booked"
    else "pending"
    end
  end

  def advance_status! = update!(status: derived_status)

  private

  def files_must_be_supported
    files.each do |file|
      errors.add(:files, "は画像（JPEG・PNG など）か PDF にしてください") unless ACCEPTED_TYPES.include?(file.content_type)
    end
  end
end
