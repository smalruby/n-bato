# 成立した決議の議案を、記録に反映した(イベント。日付は applied_on)。docs/adr/0038
# 役員の選任は役員の任期を作り、理事長・副理事長の互選は任期の役名を変えて登記の事由を作り、事業報告の承認は承認の節目を記録する。
# 外に効く出来事なので、元に戻せない操作(ADR-0007)。1 つの議案に 1 つ。
class ResolutionItem::Application < ApplicationRecord
  include EventRecord

  event_of :applied_on, entry: :apply!

  belongs_to :resolution_item
  belongs_to :applied_by, class_name: "User", optional: true

  def self.model_name_label = "議案の反映"

  def audit_fiscal_year = resolution_item&.resolution&.then { FiscalYear.for(it.proposed_on).year }

  def self.apply!(item, by: Current.user, on: Date.current)
    resolution = item.resolution
    raise ArgumentError, "もう記録に反映してあります" if item.applied?
    raise ArgumentError, "決議が成立していません" unless resolution.established?
    raise ArgumentError, "この議案は記録に反映するものではありません" if item.kind == "general"

    date = resolution.established_on
    # 操作の外で呼ばれても 1 つの操作にする。途中で失敗したら、途中までの変更を残さない(セーブポイント)
    Audit.operation do
      transaction(requires_new: true) do
        # 二度押しで、もう一方が先に反映していないか(古い記録を読んでいないか)。最後の網は一意の索引
        raise ArgumentError, "もう記録に反映してあります" if exists?(resolution_item_id: item.id)

        reflect!(item, resolution, date, by)
        application = create!(resolution_item: item, applied_on: on, applied_by: by)
        Audit.final!("決議「#{resolution.title}」の「#{item.title}」を記録に反映した")
        application
      end
    end
  rescue ActiveRecord::RecordNotUnique
    # 二度押しで、もう一方が先に反映した(古い記録を読んでいた)。セーブポイントごと取り消してある
    raise ArgumentError, "もう記録に反映してあります"
  end

  def self.reflect!(item, resolution, date, by)
    case item.kind
    when "officer_mutual_election"
      # 理事として選任済みの任期の役名を、理事長・副理事長に変える(就任は互選の日)
      item.appointments.each do |a|
        term = OfficerTerm.where(person_id: a.fetch("person_id"), role: "director").order(:starts_on).last or
          raise ActiveRecord::RecordNotFound, "互選の対象の理事の任期がありません"
        term.update!(role: a.fetch("role"))
        if term.representative?
          term.registrations.create!(kind: "representative_change", cause_on: date, due_on: date + Registration::DEADLINE_DAYS,
            note: "#{term.person.name}（#{term.role_label}）の就任・重任")
        end
      end
    when "officer_election"
      item.appointments.each do |a|
        OfficerTerm.create!(person_id: a.fetch("person_id"), role: a.fetch("role"), starts_on: date,
          ends_on: date.advance(years: OfficerTerm::TERM_YEARS).yesterday,
          appointed_by: "#{resolution.body_label}「#{resolution.title}」（#{date}）")
      end
    when "annual_report_approval"
      AnnualReport::Milestone.record!(AnnualReport.find_by!(fiscal_year: item.fiscal_year), "approved", on: date, by:)
    end
  end
  private_class_method :reflect!
end
