# 総会・理事会の決議。書面決議(みなし決議)は、議決権を持つ全員の同意がそろった日に成立する。
class Resolution < ApplicationRecord
  BODIES = { "general_meeting" => "総会", "board" => "理事会" }.freeze
  METHODS = { "written" => "書面による決議（みなし決議）", "meeting" => "会議" }.freeze

  belongs_to :proposer, class_name: "Person"
  belongs_to :minutes_author, class_name: "Person", optional: true
  has_many :items, -> { order(:position, :id) }, class_name: "ResolutionItem", dependent: :destroy
  has_many :consents, dependent: :destroy
  accepts_nested_attributes_for :items, allow_destroy: true, reject_if: ->(a) { a["title"].blank? }

  validates :body, inclusion: { in: BODIES.keys }
  validates :voting_method, inclusion: { in: METHODS.keys }
  validates :title, :proposed_on, presence: true

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

  def article_reference
    refs = (Organization.current.settings || {})["written_resolution_articles"] || {}
    refs[body].presence || "定款"
  end
end
