# 所轄庁へ出す「事業報告書等」の各書類と、全部をまとめた PDF。
class FilingsController < ApplicationController
  layout "print"

  DOCUMENTS = {
    "letter" => "事業報告書等提出書", "business_report" => "事業報告書",
    "activity" => "活動計算書", "notes" => "計算書類の注記", "balance_sheet" => "貸借対照表", "inventory" => "財産目録",
    "officer_roster" => "年間役員名簿", "member_roster" => "社員のうち10人以上の者の名簿"
  }.freeze

  before_action :load_report

  def show
    @docs = [ DOCUMENTS.keys.find { it == params[:doc] } || raise(ActionController::RoutingError, "unknown document") ]
    @title = DOCUMENTS[@docs.first]
    respond
  end

  def pack
    @docs = DOCUMENTS.keys
    @title = "事業報告書等一式"
    respond
  end

  private

  def load_report
    @annual_report = AnnualReport.find_by!(fiscal_year: params[:year])
    @fiscal_year = @annual_report.fiscal_year_object
    @statement = Ledger::Book.new.statement(@fiscal_year.year)
    @report = Ledger::Report.new(@statement)
    @organization = Organization.current
  end

  def respond
    respond_to do |format|
      format.html { render :documents }
      format.pdf do
        @pdf = true
        send_data PdfRenderer.render(render_to_string(:documents, formats: [ :html ])),
                  filename: "#{@fiscal_year.year}-#{@docs.one? ? @docs.first : 'pack'}.pdf", type: "application/pdf", disposition: "inline"
      end
    end
  end
end
