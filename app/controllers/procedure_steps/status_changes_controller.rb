# 手順を済みにする・対象外にする・済みを取り消す(状態の変化を作る。docs/adr/0008・0038)。
# status: done(済みにする。completed_on)・skipped(対象外にする。reason)・open(済みを取り消す)。
class ProcedureSteps::StatusChangesController < ApplicationController
  NOTICES = {"done" => "済みにしました", "skipped" => "対象外にしました", "open" => "済みを取り消しました"}.freeze
  ALREADY = {"done" => "もう済みにしてあります", "skipped" => "もう対象外にしてあります", "open" => "まだ済みにしていません"}.freeze

  before_action :set_step

  def create
    status = params[:status].presence_in(NOTICES.keys) or return back(alert: "状態が分かりません")

    if status == "done" && @step[:status] != "done" && (blocked = @step.complete_blocked_reason)
      return back(alert: blocked.message)
    end

    changed = ProcedureStep::StatusChange.change!(@step, status:, on: completed_on, reason: params[:reason].to_s, by: Current.user)
    # 同じ状態のとき(二度押しなど)は何も変えていないので、「元に戻せます」とは言わない
    return back(notice: "#{@step.definition.title}は#{ALREADY.fetch(status)}") unless changed

    back(step: (status == "open") ? @step.key : @run.next_step&.key || @step.key, notice: notice_for(status))
  rescue ArgumentError => e
    back(alert: e.message)
  end

  private

  def notice_for(status)
    title = @step.definition.title
    return "済みを取り消しました" if status == "open"
    return "#{title}を記録しました" if status == "done" && @step.definition.final?

    "#{title}を#{NOTICES.fetch(status)}(元に戻せます)"
  end

  def completed_on
    params[:completed_on].presence&.then { Date.parse(it) } || Date.current
  rescue Date::Error
    raise ArgumentError, "日付を入れてください"
  end

  def back(step: @step.key, **flash) = redirect_to(procedure_path(@run, step:), **flash)

  def audit_scope = "procedure:#{params[:procedure_id]}"

  def set_step
    @run = ProcedureRun.find(params[:procedure_id])
    @step = @run.step(params[:step_key])
    raise ActiveRecord::RecordNotFound unless @step.definition
  end
end
