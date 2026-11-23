class RegistrationFilings::CompletionsController < RegistrationFilings::EventsController
  def create
    RegistrationFiling::Completion.complete!(@filing, completed_on: date_param, by: Current.user)
    done "登記が完了したことを記録しました。登記事項証明書を取って中身を確かめてください"
  rescue ArgumentError => e
    failed(e)
  end
end
