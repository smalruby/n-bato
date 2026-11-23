class RegistrationFilings::WithdrawalsController < RegistrationFilings::EventsController
  def create
    RegistrationFiling::Withdrawal.withdraw!(@filing, withdrawn_on: date_param, reason: params[:reason], by: Current.user)
    done "取り下げたことを記録しました。登記することは、新しい申請に入れ直せます"
  rescue ArgumentError => e
    failed(e)
  end
end
