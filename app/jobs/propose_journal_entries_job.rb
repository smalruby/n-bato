class ProposeJournalEntriesJob < ApplicationJob
  queue_as :default

  def perform(voucher) = Bookkeeper::ProposalGenerator.new(voucher).call
end
