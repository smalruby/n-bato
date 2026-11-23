class JournalProposalsController < ApplicationController
  before_action { @proposal = JournalProposal.find(params[:id]) }

  def approve
    return redirect_to(@proposal.voucher, alert: "この提案はすでに処理済みです") unless @proposal.proposed?

    @proposal.approve!(Current.user, proposal_params)
    redirect_to @proposal.voucher, notice: "仕訳を承認して記帳しました（会計王に未取り込み）"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to @proposal.voucher, alert: e.record.errors.full_messages.join(" / ")
  end

  def reject
    @proposal.reject!(Current.user) if @proposal.proposed?
    redirect_to @proposal.voucher, notice: "提案を却下しました"
  end

  private

  def proposal_params
    params.fetch(:journal_proposal, {}).permit(:entry_date, :amount, :debit_account_id, :debit_department_id,
                                               :credit_account_id, :credit_department_id, :summary, :sub_summary)
  end
end
