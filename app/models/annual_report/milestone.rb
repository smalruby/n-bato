# 事業報告の節目の日付を記録した(イベント。日時は recorded_at、記録した日付は dated_on)。docs/adr/0038
# 節目は 5 つ: 総会で承認した・所轄庁に提出した・貸借対照表を公告した・出し直しが要る(決まりで付ける)・出し直した。
# 事業報告のいまの状態(approved_on など)は、節目の種類ごとに最後の記録(id の順)の日付から決まる。dated_on が空なら「日付を消した」。
# 記録するのは、事業報告の画面(日付の欄)・手続きの手順を済みにしたとき・決議の反映・締めた年度を直したとき(出し直しが要る)。
class AnnualReport::Milestone < ApplicationRecord
  include EventRecord

  event_of :recorded_at, entry: :record!

  # 種類 => [事業報告の列, 名前]
  KINDS = {
    "approved" => ["approved_on", "総会の承認日"],
    "submitted" => ["submitted_on", "所轄庁への提出日"],
    "bs_published" => ["bs_published_on", "貸借対照表の公告日"],
    "resubmit_needed" => ["resubmit_needed_on", "出し直しが要るとした日"],
    "resubmitted" => ["resubmitted_on", "出し直した日"]
  }.freeze

  belongs_to :annual_report
  belongs_to :recorded_by, class_name: "User", optional: true

  validates :kind, inclusion: {in: KINDS.keys}

  def self.model_name_label = "事業報告の節目"
  def self.column_for(kind) = KINDS.fetch(kind).first
  def self.kind_for(column) = KINDS.find { |_, (col, _)| col == column.to_s }&.first
  def self.audit_state_owner(change) = AnnualReport.find_by(id: change.value("annual_report_id"))

  def audit_fiscal_year = annual_report&.fiscal_year
  def kind_label = KINDS.fetch(kind).last

  # on: 日付(空なら消す)。いまの日付と同じなら何もしない(nil を返す)。
  # automatic: 決まりで付けたとき(出し直しが要る)。操作の名前は付けない(包んでいる操作の名前を残す)。
  def self.record!(report, kind, on:, automatic: false, by: Current.user, at: Time.current)
    column = column_for(kind)
    on = ActiveModel::Type::Date.new.cast(on)
    return if report[column] == on

    # 操作の外(rake・運用のスクリプト)で呼ばれても、列とイベントを 1 つの操作にする(入れ子なら外側の操作にまとめる)
    Audit.operation do
      transaction(requires_new: true) do
        # 事業報告を先に書く(元に戻すの表示が「提出日 → 2026/06/28」になるように)
        report.apply_state!(column => on)
        milestone = create!(annual_report: report, kind:, dated_on: on, automatic:, recorded_by: automatic ? nil : by, recorded_at: at)
        Audit.label!("#{report.fiscal_year}年度の事業報告: #{milestone.kind_label}を#{on ? "#{on.strftime("%Y/%m/%d")} にした" : "消した"}") unless automatic
        milestone
      end
    end
  end
end
