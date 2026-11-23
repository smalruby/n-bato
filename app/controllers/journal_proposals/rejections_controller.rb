# AI の提案の却下(イベントを作る)。docs/adr/0008。
class JournalProposals::RejectionsController < ApplicationController
  def create
    proposal = JournalProposal.find(params[:journal_proposal_id])
    JournalProposal::Rejection.reject!(proposal, by: Current.user)
    redirect_to proposal.voucher, notice: "提案を却下しました"
  end
end
