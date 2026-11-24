namespace :backup do
  desc "いまのデータを S3 に送る(本番: bin/kamal app exec --reuse 'bin/rails backup:create')"
  task create: :environment do
    abort "NBATO_BACKUP_BUCKET などの設定がありません" unless Backup.configured?
    puts "送った: #{Backup.run!}"
  end

  desc "取り出したバックアップを確かめる(bin/rails 'backup:verify[DIR]')。件数だけを出す"
  task :verify, [:dir] => :environment do |_, args|
    result = Backup::Verification.new(args.fetch(:dir)).run
    result.databases.each { |name, status| puts "db #{name}: #{status}" }
    result.tables.each { |name, count| puts "table #{name}: #{count}" }
    puts "blobs checked: #{result.blobs}"
    if result.ok?
      puts "OK"
    else
      puts result.problems
      abort "NG: #{result.problems.size} 件"
    end
  end
end
