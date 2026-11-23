# 事業ごとの主な活動を書き換える(定款と事業の要約の画面から、自動保存)。
class ProgramProfilesController < ApplicationController
  include AutosaveResponse

  def update
    profile = ProgramProfile.for(params[:id])
    profile.activities = params.require(:program_profile)[:activities].to_s.strip
    Audit.label!("主な活動を直した: 部門 #{profile.code}")
    profile.save
    respond_to do |format|
      format.json { autosave_response(profile) }
      format.html { redirect_to articles_path }
    end
  end

  private

  def audit_scope = "articles"
end
