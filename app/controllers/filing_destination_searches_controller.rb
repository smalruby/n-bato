# 提出先を AI に調べてもらう(長いイベントを作る。docs/adr/0028)。送るのは法人の所在地だけ。
class FilingDestinationSearchesController < ApplicationController
  def create
    back = params[:from] == "setup" ? setup_path(step: 2) : filing_destinations_path
    return redirect_to(back, alert: "AI の鍵(ANTHROPIC_API_KEY)が設定されていないので、AI には調べてもらえません。窓口を手で入れてください") unless Bookkeeper::Client.configured?

    address = params[:address].to_s.strip.presence || Organization.current.address.to_s
    return redirect_to(back, alert: "法人の所在地が空です。先に所在地を入れてください") if address.blank?

    FilingDestinationSearch.request!(address:, by: Current.user)
    redirect_to back, notice: "提出先を AI に調べてもらっています。できるまで、この画面を自動で読み込み直します"
  end

  private

  def audit_scope = "filing_destinations"
end
