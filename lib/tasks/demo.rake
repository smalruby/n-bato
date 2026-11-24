# 架空のデータだけの手元の環境(issue #14)。ふつうは bin/demo から使う。
namespace :demo do
  desc "架空のデータの DB(storage/demo.sqlite3)を作り直す。NBATO_DEMO=1 のときだけ動く 例: NBATO_DEMO=1 bin/rails demo:reset"
  task reset: :environment do
    db = ActiveRecord::Base.connection_db_config
    # 実データの入った DB(development.sqlite3 など)を消さないよう、demo.sqlite3 のときだけ動く
    unless Rails.env.development? && ENV["NBATO_DEMO"].present? && File.basename(db.database) == "demo.sqlite3"
      abort "demo:reset は NBATO_DEMO=1 の development でだけ動きます(いまの DB: #{db.database})"
    end

    # パスワードは NBATO_DEMO_PASSWORD か、tmp/demo_password(git 管理外)。無ければ乱数で作ってそこに書く
    password_file = Rails.root.join("tmp/demo_password")
    password = ENV["NBATO_DEMO_PASSWORD"].presence || (password_file.read.strip.presence if password_file.exist?)
    unless password
      password = SecureRandom.alphanumeric(20)
      FileUtils.mkdir_p(password_file.dirname)
      File.write(password_file, "#{password}\n", perm: 0o600)
    end

    ActiveRecord::Base.connection_pool.disconnect!
    ActiveRecord::Tasks::DatabaseTasks.purge(db)
    ActiveRecord::Tasks::DatabaseTasks.load_schema(db)
    ActiveRecord::Base.establish_connection(db)
    FileUtils.rm_rf(Rails.root.join("storage/demo_files"))

    require Rails.root.join("db/demo/seed").to_s
    seed = Demo.seed!(password:)
    puts "架空のデータを入れました(#{db.database})"
    puts "  ログイン: #{Demo::EMAIL} / パスワード: #{ENV["NBATO_DEMO_PASSWORD"].present? ? "NBATO_DEMO_PASSWORD" : password_file.relative_path_from(Rails.root)}"
    puts "  年度 #{FiscalPeriod.years.join("・")}(いまの年度 #{seed.year})、仕訳 #{JournalEntry.count} 件、人 #{Person.count} 人、決議 #{Resolution.count} 件"
  end
end
