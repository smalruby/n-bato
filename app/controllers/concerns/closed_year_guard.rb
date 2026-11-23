# 締めた年度のデータを変えるときは理由を書いてもらう(デザインシステム「年度」)。HTML の画面用。
module ClosedYearGuard
  extend ActiveSupport::Concern

  private

  # 締めた年度にかかるなら理由を確かめる。理由が無ければ false(呼び出し側で画面に戻す)。
  def closed_year_reason_ok?(years, what)
    closed = Array(years).compact.uniq.select { FiscalPeriod.for(it)&.closed? }
    return true if closed.empty?

    reason = params[:reason].to_s.strip
    if reason.empty?
      @reason_needed = "#{closed.map { FiscalPeriod.for(it).label }.join('・')}は締めた年度です。直す理由を書いてください。"
      return false
    end
    Audit.reason!(reason)
    FiscalPeriod.changed_after_close!(closed)
    Audit.label!("締めた年度(#{closed.map { "#{it}年度" }.join('・')})の#{what}を直した")
    true
  end

  # 年度の範囲にかかる年度(役員の任期など)
  def fiscal_years_between(from, to)
    return [] unless from && to
    (FiscalYear.for(from).year..FiscalYear.for(to).year).to_a
  end
end
