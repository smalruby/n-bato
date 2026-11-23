# 手元の Docker 用のメールの受け箱(app/models/local_mailbox.rb)を、送り方の 1 つとして登録する。
Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method :local_mailbox, LocalMailbox, location: Rails.root.join("storage/mails")
end
