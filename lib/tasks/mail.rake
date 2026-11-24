namespace :mail do
  desc "手元の受け箱(storage/mails)のいちばん新しいメールの件名・宛先・本文を表示する"
  task latest: :environment do
    mail = LocalMailbox.latest(Rails.root.join("storage/mails"))
    abort "受け箱にメールはありません(NBATO_MAIL_DELIVERY=local_mailbox のときだけ、ここに届きます)" unless mail

    puts "件名: #{mail.subject}", "宛先: #{Array(mail.to).join(", ")}", "日時: #{mail.date}", "", LocalMailbox.text_of(mail)
  end
end
