# 年度の操作(デザインシステム「年度」): 次の年度を始める・締めを解く。締めるのは手続き「事業報告書等の提出」の最後の手順。
class FiscalPeriodsController < ApplicationController
  def start_next
    Audit.final!("#{FiscalPeriod.next_year}年度を始めた")
    period = FiscalPeriod.start_next!
    redirect_to year_switch_path(period.year), notice: "#{period.label}を始めました。前の年度の科目と部門・会員と役員・法人情報を写しました"
  end

  def reopen
    period = FiscalPeriod.find_by!(year: params[:id])
    Audit.final!("#{period.label}の締めを解いた")
    period.reopen!(reason: params[:reason])
    redirect_to fiscal_year_path(period.year), notice: "#{period.label}の締めを解きました(理由は変更の記録に残りました)"
  rescue ArgumentError => e
    redirect_to fiscal_year_path(params[:id]), alert: e.message
  end
end
