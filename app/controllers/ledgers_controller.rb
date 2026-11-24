class LedgersController < ApplicationController
  layout "print"

  def index
    load_common
    @title = "総勘定元帳"
    @accounts = (@statement.opening_balances.keys + @statement.movements.keys).uniq.sort_by(&:code)
    @ledgers = @accounts.to_h { [it, @book.account_ledger(it, @fiscal_year.year)] }
    respond(:index)
  end

  def show
    load_common
    @account = Account.in_year(@fiscal_year.year).find_by!(code: params[:account_code])
    @title = "元帳 #{@account.display_name}"
    @ledgers = {@account => @book.account_ledger(@account, @fiscal_year.year)}
    respond(:index)
  end

  private

  def load_common
    @fiscal_year = FiscalYear.new(Integer(params[:fiscal_year_year]))
    @book = Ledger::Book.new
    @statement = @book.statement(@fiscal_year.year)
    @organization = Organization.current
  end

  def respond(template)
    respond_to do |format|
      format.html { render template }
      format.pdf do
        @pdf = true
        send_data PdfRenderer.render(render_to_string(template, formats: [:html])),
          filename: "#{@fiscal_year.year}-ledger.pdf", type: "application/pdf", disposition: "inline"
      end
    end
  end
end
