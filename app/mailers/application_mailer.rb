class ApplicationMailer < ActionMailer::Base
  # 差出人は環境変数 NBATO_MAIL_FROM から(デプロイの相談 第3回: 画面で設定できるようにするまでのつなぎ)。
  # SES で確かめたドメイン(smalruby.jp)のアドレスでないと送れない。
  default from: -> { ENV.fetch("NBATO_MAIL_FROM", "from@example.com") },
          reply_to: -> { ENV["NBATO_MAIL_REPLY_TO"].presence }
  layout "mailer"
end
