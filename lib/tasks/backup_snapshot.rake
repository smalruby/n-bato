namespace :backup do
  desc "書く前のバックアップ: 本体の DB を storage/backups/ に写す(新しい 20 世代を残す)"
  task snapshot: :environment do
    puts "書く前のバックアップ: #{Backup::Snapshot.new.create!}"
  end

  desc "書く前のバックアップの一覧"
  task snapshots: :environment do
    puts Backup::Snapshot.new.names
  end

  desc "書く前のバックアップを本体の DB に戻す(アプリを止めてから。bin/prod-restore が使う)"
  task :restore_snapshot, [:name] => :environment do |_, args|
    puts "戻した: #{Backup::Snapshot.new.restore!(args.fetch(:name))}"
  end
end
