module Compliance
  # 法人の義務と期限の一覧(事業報告書等の提出、総会、役員の改選、登記、貸借対照表の公告)。
  class Checklist
    Item = Data.define(:category, :title, :due_on, :status, :path, :note) do
      def overdue? = status == :overdue
      def done? = status == :done
      def status_label = {overdue: "期限切れ", upcoming: "近い", open: "未完了", done: "完了"}[status]
    end

    UPCOMING_DAYS = 90

    def initialize(today: Date.current, organization: Organization.current)
      @today = today
      @org = organization
    end

    def items = (annual_reports + general_meetings + officer_terms + registrations).sort_by { [status_rank(it.status), it.due_on || Date.new(9999)] }
    def open_items = items.reject(&:done?)

    private

    include Rails.application.routes.url_helpers

    def status_for(due_on, done)
      return :done if done
      return :open if due_on.nil? # 期限が分からない(例: 住所を移した日が不明)
      return :overdue if due_on < @today
      return :upcoming if due_on <= @today + UPCOMING_DAYS

      :open
    end

    def status_rank(status) = %i[overdue upcoming open done].index(status)

    # 期限を確認し始める年度(settings.compliance_from。無ければ第 1 期)
    def completed_years
      first = (@org.settings || {})["compliance_from"].presence&.to_i || @org.first_fiscal_year || FiscalYear.current.year
      (first..(FiscalYear.for(@today).year - 1)).to_a
    end

    def annual_reports
      reports = AnnualReport.all.index_by(&:fiscal_year)
      completed_years.flat_map do |year|
        r = reports[year]
        due = Date.new(year + 1, 6, 30)
        list = [Item.new("提出", "#{year}年度の事業報告書等を所轄庁に提出", due, status_for(due, r&.submitted_on), r ? annual_report_path(year) : new_annual_report_path(year: year),
          r&.submitted_on ? "#{r.submitted_on} 提出" : nil)]
        if r&.approved_on
          list << Item.new("公告", "#{year}年度の貸借対照表を公告", r.approved_on + 30, status_for(r.approved_on + 30, r.bs_published_on), annual_report_path(year),
            "総会承認 #{r.approved_on}。遅滞なく公告（期限の目安は承認から 30 日）")
        end
        list
      end
    end

    # 通常総会は事業年度開始から 3 か月以内(定款)。総会の決議(会議または書面決議)が成立していれば完了とみなす。
    def general_meetings
      resolutions = Resolution.where(body: "general_meeting").includes(:consents).to_a
      completed_years.map { it + 1 }.select { it <= FiscalYear.for(@today).year }.map do |year|
        fy = FiscalYear.new(year)
        due = fy.starts_on.advance(months: 3).yesterday
        held = resolutions.select { (d = it.established_on) && fy.range.cover?(d) }.map(&:established_on).min
        Item.new("総会", "#{year}年度の通常総会（前年度の事業報告・決算の承認）", due, status_for(due, held), resolutions_path, held ? "#{held} 成立" : nil)
      end
    end

    def officer_terms
      expired = OfficerTerm.serving_on(@today).select { it.expired_on?(@today) }
      soon = OfficerTerm.serving_on(@today).reject { it.expired_on?(@today) }.select { it.ends_on <= @today + UPCOMING_DAYS }
      list = []
      if expired.any?
        list << Item.new("役員", "役員の改選（任期満了 #{expired.map(&:ends_on).min}、#{expired.size} 人）", expired.map(&:ends_on).min, :overdue, resolutions_path,
          "定款の伸長規定で職務は続いているが、総会で改選が必要")
      end
      if soon.any?
        list << Item.new("役員", "役員の任期満了が近い（#{soon.map(&:ends_on).min}）", soon.map(&:ends_on).min, :upcoming, resolutions_path, "総会で改選する")
      end
      list
    end

    def registrations
      Registration.includes(officer_term: :person).map do |r|
        Item.new("登記", "#{r.kind_label}: #{r.note}", r.due_on, status_for(r.due_on, r.registered_on), registrations_path, r.registered_on ? "#{r.registered_on} 登記" : nil)
      end
    end
  end
end
