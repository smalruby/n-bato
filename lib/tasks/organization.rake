namespace :organization do
  desc "法人の情報を YAML から読み込む(実データは data/ に置く) 例: bin/rails 'organization:load[data/organization.yml]'"
  task :load, [ :path ] => :environment do |_, args|
    conf = YAML.load_file(args[:path] || "data/organization.yml", permitted_classes: [ Date ])
    org = Organization.first || Organization.new
    org.update!(conf.fetch("organization"))
    # 部門は年度ごとのデータセット。締めていない年度すべてに入れる。
    FiscalPeriod.ensure!
    years = FiscalPeriod.ordered.reject(&:closed?).map(&:year)
    conf.fetch("departments", {}).each do |code, full_name|
      years.each do |year|
        dept = Department.find_or_initialize_by(fiscal_year: year, code: code)
        dept.name ||= code.to_i == Department::ADMIN_CODE ? "管理部門" : "#{full_name[0, 1]}事業"
        dept.update!(full_name: full_name)
      end
    end
    puts "#{org.name}: 部門 #{Department.count} 件"
  end
end

namespace :users do
  desc "ログインできる人を作る 例: EMAIL=a@example.com PASSWORD=... NAME=理事長 bin/rails users:create"
  task create: :environment do
    user = User.find_or_initialize_by(email_address: ENV.fetch("EMAIL"))
    user.update!(password: ENV.fetch("PASSWORD"), name: ENV["NAME"])
    puts "#{user.email_address} を登録しました"
  end
end
