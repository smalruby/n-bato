# AI の提案の承認(イベントを作る)。docs/adr/0008: コントローラーは確かめ・呼び出し・表示の準備だけ。
class JournalProposals::ApprovalsController < ApplicationController
  def create
    proposal = JournalProposal.find(params[:journal_proposal_id])
    return redirect_to(proposal.voucher, alert: "この提案はすでに処理済みです") unless proposal.proposed?

    JournalProposal::Approval.approve!(proposal, by: Current.user, entry: entry_params)
    redirect_to proposal.voucher, notice: "仕訳を承認して記帳しました（会計王に未取り込み）"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to proposal.voucher, alert: e.record.errors.full_messages.join(" / ")
  end

  private

  def entry_params = params.fetch(:journal_proposal, {}).permit(*JournalProposal::ENTRY_FIELDS)
end
