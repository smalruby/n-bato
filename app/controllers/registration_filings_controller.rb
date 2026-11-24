# 登記の申請(長いイベント)。始める・登記することを足す/外す・添付する決議を選ぶ・書類(PDF)。docs/adr/0031
class RegistrationFilingsController < ApplicationController
  DOCUMENTS = { "cover" => "書面により提出する添付書面の内訳", "mutual_election" => "理事の互選書", "articles" => "定款" }.freeze

  before_action :set_filing, except: :create
  before_action :forbid_auditor, except: %i[show document]

  def create
    regs = Registration.where(id: Array(params[:registration_ids])).to_a
    filing = RegistrationFiling.start!(regs)
    redirect_to filing, notice: "登記の申請を始めました。書類を作って、申請用総合ソフトで送ってください"
  rescue ArgumentError => e
    redirect_to registrations_path, alert: e.message
  end

  def show
    @statement = @filing.statement
    @available = Registration.includes(:registration_filing, officer_term: :person).chronological.select(&:available?)
    @resolutions = ::Resolution.recent.to_a
    @online = RegistrationOnline.status
  end

  # 添付する決議(社員総会議事録・理事会議事録)を選ぶ
  def update
    @filing.update!(params.require(:registration_filing).permit(:general_meeting_resolution_id, :board_resolution_id, :note))
    redirect_to registration_filing_path(@filing, anchor: "documents"), notice: "保存しました"
  end

  def include
    @filing.include!(Registration.find(params[:registration_id]))
    redirect_to registration_filing_path(@filing, anchor: "items"), notice: "登記することを足しました"
  rescue ArgumentError => e
    redirect_to registration_filing_path(@filing, anchor: "items"), alert: e.message
  end

  def exclude
    @filing.exclude!(Registration.find(params[:registration_id]))
    redirect_to registration_filing_path(@filing, anchor: "items"), notice: "登記することから外しました"
  rescue ArgumentError => e
    redirect_to registration_filing_path(@filing, anchor: "items"), alert: e.message
  end

  # 添付書類(紙で郵送する)。HTML で見て、PDF で印刷する。
  def document
    @doc = DOCUMENTS.keys.find { it == params[:doc] } or raise ActionController::RoutingError, "unknown document"
    @title = DOCUMENTS[@doc]
    @organization = Organization.current
    @statement = @filing.statement
    respond_to do |format|
      format.html { render "registration_filings/document", layout: "print" }
      format.pdf do
        @pdf = true
        html = render_to_string("registration_filings/document", layout: "print", formats: [ :html ])
        send_data PdfRenderer.render(html), filename: "registration-#{@filing.id}-#{@doc}.pdf", type: "application/pdf", disposition: "inline"
      end
    end
  end

  private

  def set_filing = @filing = RegistrationFiling.find(params[:id])
  def forbid_auditor = (redirect_to(registrations_path, alert: "監査の役割では直せません") if Current.user&.auditor?)
  def audit_scope = "registrations"
end
