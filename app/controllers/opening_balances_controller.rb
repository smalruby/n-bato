class OpeningBalancesController < ApplicationController
  def index
    @balances = OpeningBalance.includes(:account).where(fiscal_year: Current.working_year).order("accounts.code").references(:account)
    @balance = OpeningBalance.new(fiscal_year: Current.working_year)
  end

  def create
    @balance = OpeningBalance.find_or_initialize_by(fiscal_year: params.dig(:opening_balance, :fiscal_year), account_id: params.dig(:opening_balance, :account_id))
    @balance.amount = params.dig(:opening_balance, :amount)
    if @balance.save
      redirect_to opening_balances_path, notice: "期首残高を登録しました"
    else
      redirect_to opening_balances_path, alert: @balance.errors.full_messages.join(" / ")
    end
  end

  def destroy
    OpeningBalance.find(params[:id]).destroy!
    redirect_to opening_balances_path, notice: "削除しました"
  end
end
