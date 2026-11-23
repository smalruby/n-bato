class FiscalYearsController < ApplicationController
  def index
    @statements = Ledger::Book.new.statements.reverse
  end

  def show
    @fiscal_year = FiscalYear.new(Integer(params[:year]))
    @statement = Ledger::Book.new.statement(@fiscal_year.year)
    @report = Ledger::Report.new(@statement)
    @organization = Organization.current
  end
end
