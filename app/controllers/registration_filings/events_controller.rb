# 登記の申請の詳細のイベント(申請した・受付・補正・完了・取下げ)を作るコントローラーの共通部分。docs/adr/0008・0031
class RegistrationFilings::EventsController < ApplicationController
  before_action { @filing = RegistrationFiling.find(params[:registration_filing_id]) }
  before_action { redirect_to(registration_filing_path(@filing), alert: "監査の役割では記録できません") if Current.user&.auditor? }

  private

  def date_param(key = :on)
    Date.parse(params[key].to_s)
  rescue Date::Error
    raise ArgumentError, "日付を入れてください"
  end

  def done(notice) = redirect_to(registration_filing_path(@filing), notice:)
  def failed(e) = redirect_to(registration_filing_path(@filing), alert: e.message)
  def audit_scope = "registrations"
end
