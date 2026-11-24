# 成立した決議の議案を記録に反映する(反映のイベントを作る。元に戻せない操作。docs/adr/0008・0038)。
class ResolutionItems::ApplicationsController < ApplicationController
  def create
    resolution = ::Resolution.find(params[:resolution_id])
    item = resolution.items.find(params[:item_id])
    ResolutionItem::Application.apply!(item, by: Current.user)
    redirect_to resolution, notice: "「#{item.title}」を記録に反映しました"
  rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    raise if resolution.nil? || item.nil?

    redirect_to resolution, alert: e.message
  end

  private

  def audit_scope = "resolutions"
end
