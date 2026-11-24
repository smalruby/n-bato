# 定款と事業(デザインシステム Articles、見直し第13回)。年度に依存しない読むためのページ。
# タブ: 要約・定款の全文・変更の記録。版を選べる(既定は現行の版)。事業ごとの主な活動はここで書き換える(操作履歴に残る)。
class ArticlesController < ApplicationController
  undoable_screen
  TABS = {"summary" => "要約", "full" => "定款の全文", "history" => "変更の記録"}.freeze

  def index
    @versions = ArticleVersion.ordered.to_a
    @version = @versions.find { it.number == params[:v].to_i } if params[:v].present?
    @version ||= @versions.last
    @tab = params[:tab].presence_in(TABS.keys) || "summary"
    @q = params[:q].to_s.strip
    @profiles = ProgramProfile.all.index_by(&:code)
  end

  # 右ペインに出す条文(ArticleRef)。その年度の時点の版の条を出す。
  def show
    @year = (params[:year].presence || Current.working_year)&.to_i
    @version = ArticleVersion.for_year(@year)
    @article = @version&.document&.article(params[:id])
    render layout: false
  end
end
