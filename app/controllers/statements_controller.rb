class StatementsController < ApplicationController
  layout "print"

  def show
    @kind = Ledger::Report::KINDS.keys.find { it == params[:kind] }
    raise ActionController::RoutingError, "unknown statement" unless @kind

    @fiscal_year = FiscalYear.new(Integer(params[:fiscal_year_year]))
    @statement = Ledger::Book.new.statement(@fiscal_year.year)
    @report = Ledger::Report.new(@statement)
    @organization = Organization.current
    @title = Ledger::Report::KINDS[@kind]

    respond_to do |format|
      format.html { render :show }
      format.pdf do
        @pdf = true
        html = render_to_string(:show, formats: [:html])
        send_data PdfRenderer.render(html), filename: "#{@fiscal_year.year}-#{@kind}.pdf", type: "application/pdf", disposition: "inline"
      end
    end
  end
end
