namespace :users do
  desc "監査の役割(閲覧だけ)の利用者を作る 例: bin/rails users:auditor EMAIL=kanji@example.com NAME=監事 PASSWORD=..."
  task auditor: :environment do
    user = User.find_or_initialize_by(email_address: ENV.fetch("EMAIL"))
    user.name = ENV["NAME"].presence || user.name
    user.password = ENV.fetch("PASSWORD") if ENV["PASSWORD"].present? || user.new_record?
    user.roles = %w[auditor]
    user.role = "auditor"
    user.save!
    puts "#{user.email_address}: #{user.role_label}"
  end

  desc "切り替えられる役割を決める 例: bin/rails users:roles EMAIL=kanji@example.com ROLES=auditor,clerk"
  task roles: :environment do
    user = User.find_by!(email_address: ENV.fetch("EMAIL"))
    user.roles = ENV.fetch("ROLES").split(",")
    abort "役割は #{User::ROLES.keys.join(' / ')} から選んでください" if user.roles.empty?
    user.role = user.roles.first unless user.can_use?(user.role)
    user.save!
    puts "#{user.email_address}: #{user.roles.map { User::ROLES[it] }.join('・')}(いまは#{user.role_label})"
  end
end
