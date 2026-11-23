# 提出先(所轄庁などの窓口。デザインシステム「提出先」、見直し第17回、docs/adr/0027)。年度に依存しないリソース。
# 書類の宛先・手続きの説明の「{所轄庁}」は、確かめた(確認済みの)提出先から差し込む。AI の案や、直したあと確かめていないものは使わない。
class FilingDestination < ApplicationRecord
  KINDS = {
    "authority" => "所轄庁(NPO 法人の担当)", "prefectural_tax" => "法人住民税(県)", "municipal_tax" => "法人住民税(市)",
    "registry" => "登記", "tax_office" => "税務署", "other" => "その他"
  }.freeze
  CONTENT_FIELDS = %w[kind name addressee office address phone fax email hours forms_url source].freeze
  PLACEHOLDER = "{所轄庁}".freeze
  UNSET_AUTHORITY = "(所轄庁が未設定)".freeze
  UNSET_ADDRESSEE = "(所轄庁の宛先が未設定)".freeze

  has_many :confirmations, -> { order(:confirmed_at) }, class_name: "FilingDestination::Confirmation", dependent: :destroy

  validates :kind, inclusion: { in: KINDS.keys }
  validates :origin, inclusion: { in: %w[human ai] }

  scope :ordered, -> { order(:position, :id) }

  def kind_label = KINDS[kind]
  def ai? = origin == "ai"

  # 確かめた中身の要約。中身を直すと変わり、確認済みでなくなる。
  def digest = Digest::SHA256.hexdigest(CONTENT_FIELDS.map { self[it].to_s }.join("\u0001"))
  def last_confirmation = confirmations.last
  def confirmed? = last_confirmation&.digest == digest

  def state_label
    return "確認済み" if confirmed?
    return "AI の案(人が確かめる)" if ai?

    last_confirmation ? "直したあと、まだ確かめていない" : "まだ確かめていない"
  end

  def self.confirmed_authority = where(kind: "authority").ordered.find(&:confirmed?)

  # 書類の「（あて先）」。確認済みの所轄庁が無ければ「未設定」と書く(推測で埋めない)
  def self.letter_addressee = confirmed_authority&.addressee.presence || UNSET_ADDRESSEE

  # 手続きの説明などの「{所轄庁}」を、確認済みの所轄庁の名前にする
  def self.fill(text)
    case text
    when String then text.include?(PLACEHOLDER) ? text.gsub(PLACEHOLDER, confirmed_authority&.name.presence || UNSET_AUTHORITY) : text
    when Array then text.map { fill(it) }
    else text
    end
  end
end
