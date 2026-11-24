# 総会・理事会の決議。書面決議(みなし決議)は、議決権を持つ全員の同意がそろった日に成立する。
# 長いイベント(docs/adr/0038)。詳細のイベントは、同意(Consent)・同意の取消(Consent::Cancellation)・議案の反映(ResolutionItem::Application)。
# 成立した日は、取り消していない同意から毎回決まる(列には持たない)。件名・提案日・議案などの中身は、ふつうに直してよい。
# 同意を記録した(取り消したものも)・議案を反映した決議は消せない(出来事を消さないため)。
class Resolution < ApplicationRecord
  BODIES = {"general_meeting" => "総会", "board" => "理事会"}.freeze
  METHODS = {"written" => "書面による決議（みなし決議）", "meeting" => "会議"}.freeze

  belongs_to :proposer, class_name: "Person"
  belongs_to :minutes_author, class_name: "Person", optional: true
  before_destroy :keep_events, prepend: true
  has_many :items, -> { order(:position, :id) }, class_name: "ResolutionItem", dependent: :destroy
  # 取り消していない同意(成立に数えるもの)。取り消したものも含めるときは all_consents
  has_many :consents, -> { active }, class_name: "Consent"
  has_many :all_consents, class_name: "Consent", dependent: :restrict_with_error
  accepts_nested_attributes_for :items, allow_destroy: true, reject_if: ->(a) { a["title"].blank? }

  validates :body, inclusion: {in: BODIES.keys}
  validates :voting_method, inclusion: {in: METHODS.keys}
  validates :title, :proposed_on, presence: true
  validate { items.select(&:marked_for_destruction?).filter_map(&:destroy_blocked_reason).uniq.each { errors.add(:base, it.message) } }

  def self.model_name_label = "決議"
  EDIT_INSTEAD = "代わりに: 件名・提案日・議案の中身は「編集」で直せます。"

  scope :recent, -> { order(proposed_on: :desc, id: :desc) }

  def body_label = BODIES[body]
  def method_label = METHODS[voting_method]
  def written? = voting_method == "written"

  # 議決権を持つ人(総会 = その年度の正会員、理事会 = 提案日に職務を行っている理事)
  def voters
    case body
    when "general_meeting"
      Person.joins(:memberships).merge(Membership.regular.in_fiscal_year(FiscalYear.for(proposed_on).year)).distinct.order(:id).to_a
    when "board"
      OfficerTerm.serving_on(proposed_on).select(&:director?).map(&:person).uniq
    end
  end

  def consented_people = consents.includes(:person).map(&:person)
  def pending_voters = voters - consented_people

  # 全員が同意した日(書面決議の成立日)。そろっていなければ nil。
  def established_on
    return held_on unless written?
    return nil if voters.empty? || pending_voters.any?

    consents.where(person: voters).maximum(:consented_on)
  end

  def established? = established_on.present?

  # 元に戻す・やり直すのあとに確かめる(Audit.check_states!。持ち主は同意・同意の取消の audit_state_owner)。
  # 元に戻すは検証を通さずに書くので、取り消していない同意が同じ人に 2 つになったり、反映した議案があるのに
  # 同意が減って成立しなくなったりしないかを、ここで確かめる(docs/adr/0038)。
  def state_mismatches
    list = []
    list << "取り消していない同意(同じ人に 2 つ)" if consents.group(:person_id).having("COUNT(*) > 1").exists?
    list << "成立(反映した議案があるのに成立していない)" if ResolutionItem::Application.joins(:resolution_item).exists?(resolution_items: {resolution_id: id}) && !established?
    list
  end

  # 消せないときの理由(BlockedReason)。消せるなら nil。画面の (i) と、消そうとして止めたときのエラーの文で使う。
  def destroy_blocked_reason
    if (total = all_consents.count).positive?
      cancelled = all_consents.where(id: Consent::Cancellation.select(:consent_id)).count
      BlockedReason.new(title: "この決議は消せません", reason: "書面決議の記録として残すため、同意を記録した決議は消せません(同意の記録は、取り消しても残ります)。",
                        what: "同意の記録が #{total} 件あります#{"(取り消した #{cancelled} 件を含む)" if cancelled.positive?}",
                        link_label: "同意の記録を見る(#{total} 件)", link_target: "#consents", alternative: EDIT_INSTEAD)
    elsif (applied = items.count(&:applied?)).positive?
      BlockedReason.new(title: "この決議は消せません", reason: "役員の任期・登記・事業報告の記録に効いているので、記録に反映した議案のある決議は消せません。",
                        what: "記録に反映した議案が #{applied} 件あります", link_label: "議案を見る", link_target: "#items", alternative: EDIT_INSTEAD)
    end
  end

  def article_reference
    refs = (Organization.current.settings || {})["written_resolution_articles"] || {}
    refs[body].presence || "定款"
  end

  private

  def keep_events
    return unless (blocked = destroy_blocked_reason)

    errors.add(:base, blocked.message)
    throw :abort
  end
end
