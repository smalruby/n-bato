class RegistrationFilings::SubmissionsController < RegistrationFilings::EventsController
  def create
    RegistrationFiling::Submission.submit!(@filing, submitted_on: date_param, application_number: params[:application_number], by: Current.user)
    done "申請したことを記録しました。添付書類は、申請番号を書いて郵送してください"
  rescue ArgumentError => e
    failed(e)
  end
end
