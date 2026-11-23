# 変更の記録(デザインシステム「年度」)。年度ごとに、誰が・いつ・何を・前の値・後の値・理由を一覧する。
# 締めたあとの変更だけに絞れ、監事に渡す印刷用(PDF)の形でも出せる。
class ChangesController < ApplicationController
  def index
    @year = Current.working_year
    @period = FiscalPeriod.for(@year)
    @after_close = params[:after_close] == "1" && @period&.closed_on
    changes = AuditChange.in_fiscal_year(@year).includes(audit_operation: :user).order(created_at: :desc, id: :desc)
    changes = changes.where(created_at: (@period.closed_at || @period.closed_on.end_of_day)..) if @after_close
    @changes = changes.limit(params[:print] ? nil : 500).to_a
    if params[:print]
      @title = "変更の記録 #{@period&.label}"
      render :print, layout: "print"
    end
  end
end
