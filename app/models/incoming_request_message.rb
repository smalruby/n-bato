# 依頼ごとの対話の 1 件の発言(イベント。日時は written_at)。docs/adr/0034
# 人の発言は、書いたときは下書き。AI に送ると IncomingRequestMessage::Delivery(伏せた文と、添付を送ったか)ができる。
# AI に送るのは伏せた文だけ。添付は送るかを人が選ぶ(既定は送らない)。
# AI の発言(返事と「やることの案」)は、送ったときにできる。人が「この案で決める」を押すと IncomingRequestMessage::Adoption ができる。
# 送る前の下書きだけは消せる(まだ誰にも渡っていない。住所などの個人情報を残さないため)。
class IncomingRequestMessage < ApplicationRecord
  include EventRecord

  event_of :written_at, entry: :write!

  ROLES = %w[user assistant].freeze
  # 添付は PDF と画像だけ(表計算などは読めないので、PDF にしてもらう)
  ACCEPT = %r{\A(image/(png|jpeg|gif|webp)|application/pdf)\z}

  belongs_to :incoming_request
  has_many_attached :files
  has_one :delivery, class_name: "IncomingRequestMessage::Delivery", foreign_key: :message_id, inverse_of: :message, dependent: :restrict_with_error
  has_one :adoption, class_name: "IncomingRequestMessage::Adoption", foreign_key: :message_id, inverse_of: :message, dependent: :restrict_with_error

  validates :role, inclusion: {in: ROLES}

  # 送る前の、人の下書き
  scope :drafts, -> { where(role: "user").where.missing(:delivery) }

  # 発言を書く。人の発言(role: user)は下書きになる。files は PDF と画像だけ付ける。
  def self.write!(request, role:, body:, files: [], proposal: nil, at: Time.current)
    message = create!(incoming_request: request, role:, body:, proposal:, written_at: at)
    Array(files).each { |f| message.files.attach(f) if f.respond_to?(:content_type) && f.content_type.to_s.match?(ACCEPT) }
    message
  end

  def user? = role == "user"
  def draft? = user? && delivery.nil?
  def sent? = delivery.present?
  def applied? = adoption.present?
  # AI に送った伏せた文と、添付を送ったか(送る前は空)
  def masked_body = delivery&.masked_body.to_s
  def send_attachments = delivery&.send_attachments || false

  def proposal_todos = Array(proposal&.dig("todos_new"))
  def proposal_updates = Array(proposal&.dig("todos_update"))
  def proposal_actionable? = !user? && !applied? && (proposal_todos.any? || proposal_updates.any? || proposal&.dig("request", "title").present?)
  def audit_fiscal_year = nil

  # 送る前の下書きを消す(下書きでなければ消さない)
  def discard!
    raise ArgumentError, "AI に送った発言は消せません" unless draft?

    destroy!
  end
end
