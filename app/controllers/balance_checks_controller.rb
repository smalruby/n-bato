class BalanceChecksController < ApplicationController
  def index
    @book = Ledger::Book.new
    @checks = BalanceCheck.recent.includes(:account)
    @check = BalanceCheck.new(checked_on: Date.current)
    @asset_accounts = Account.in_year(Current.working_year).ordered.where(category: "asset")
  end

  def create
    check = BalanceCheck.new(params.require(:balance_check).permit(:checked_on, :actual_amount, :note))
    check.account = Account.where(category: "asset").find_by(id: params.dig(:balance_check, :account_id))
    if check.save
      diff = check.difference
      msg = diff.zero? ? "帳簿と一致しました" : "帳簿と #{ActiveSupport::NumberHelper.number_to_delimited(diff)} 円の差があります。仕訳の漏れ（利息・手数料など）を確認してください"
      redirect_to balance_checks_path, (diff.zero? ? :notice : :alert) => msg
    else
      redirect_to balance_checks_path, alert: check.errors.full_messages.join(" / ")
    end
  end

  def destroy
    BalanceCheck.find(params[:id]).destroy!
    redirect_to balance_checks_path, notice: "削除しました"
  end
end
