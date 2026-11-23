# 登記(見直し第20回、docs/adr/0031)。登記がいること(登記の事由)と、登記の申請の一覧。年度には依存しない。
class RegistrationsController < ApplicationController
  def index
    @registrations = Registration.includes(:registration_filing, :person_address_change, :person_name_change, officer_term: :person).chronological.to_a
    @pending = @registrations.reject(&:done?)
    @done = @registrations.select(&:done?)
    @filings = RegistrationFiling.includes(:registrations).recent
    @online = RegistrationOnline.status
  end
end
