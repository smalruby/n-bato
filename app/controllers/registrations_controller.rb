class RegistrationsController < ApplicationController
  def index
    @registrations = Registration.includes(officer_term: :person).order(:due_on).where(cause_on: FiscalYear.new(Current.working_year).range)
  end

  def update
    registration = Registration.find(params[:id])
    registration.update!(params.require(:registration).permit(:registered_on, :note))
    redirect_to registrations_path, notice: "登記の記録を更新しました"
  end
end
