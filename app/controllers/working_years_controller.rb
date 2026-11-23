# 他の年度に切り替える(デザインシステム「年度」)。切り替えは set_working_year が URL の年度で行う。
# ここでは、いま見ていた画面の、切り替えた年度のものへ戻す。
class WorkingYearsController < ApplicationController
  def switch
    year = Current.working_year
    back = URI.parse(request.referer.to_s) rescue nil
    path = back&.path.presence || root_path
    path = path.sub(%r{\A/(fiscal_years|annual_reports)/\d{4}}) { "/#{$1}/#{year}" }
    query = Rack::Utils.parse_query(back&.query.to_s).except("year", "fiscal_year_year")
    # 切り替えた年度の事業報告書がまだ無いときは、一覧へ戻す(見つからない画面にしない)。
    if path.start_with?("/annual_reports/") && !AnnualReport.exists?(fiscal_year: year)
      flash[:notice] = "#{year}年度の事業報告書はまだありません。一覧から作れます。"
      path, query = annual_reports_path, {}
    end
    redirect_to [ path, query.presence&.to_query ].compact.join("?")
  end
end
