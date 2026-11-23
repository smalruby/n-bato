namespace :kaikeiou do
  desc "会計王の SIWAKE ファイル(またはそれを入れたディレクトリ)を取り込む"
  task :import, [ :path ] => :environment do |_, args|
    path = args[:path] or abort "使い方: bin/rails 'kaikeiou:import[PATH]'"
    Kaikeiou::SiwakeImporter.import_path(path).each do |r|
      status = r.created ? "取り込み" : "スキップ(#{r.skipped_reason})"
      puts "#{status}: #{r.siwake_import.filename} #{r.siwake_import.entries_count} 件"
    end
  end

  desc "会計王の勘定科目設定・部門設定の書き出しを取り込む(DIR に 勘定科目設定.txt・部門設定.txt)"
  task :master, [ :dir ] => :environment do |_, args|
    dir = args[:dir] or abort "使い方: bin/rails 'kaikeiou:master[DIR]'"
    accounts = File.join(dir, "勘定科目設定.txt")
    departments = File.join(dir, "部門設定.txt")
    if File.exist?(accounts)
      list = Kaikeiou::AccountMaster.import_accounts(File.binread(accounts))
      puts "科目: #{list.size} 件"
    end
    if File.exist?(departments)
      list = Kaikeiou::AccountMaster.import_departments(File.binread(departments))
      puts "部門: #{list.size} 件"
    end
  end

  desc "取り込んだ SIWAKE を書き出し、元のファイルと同じか確かめる"
  task :verify, [ :path ] => :environment do |_, args|
    dir = args[:path] or abort "使い方: bin/rails 'kaikeiou:verify[DIR]'"
    SiwakeImport.find_each do |si|
      original = File.join(dir, si.filename)
      next puts("元ファイルなし: #{si.filename}") unless File.exist?(original)

      same = si.to_siwake_file.to_bytes.b == File.binread(original).b
      puts "#{same ? 'OK' : 'NG'}: #{si.filename}"
    end
  end

  desc "仕訳を SIWAKE 形式で書き出す(年度指定可)"
  task :export, [ :year, :out ] => :environment do |_, args|
    entries = JournalEntry.active.chronological # 取り消した仕訳は書き出さない(docs/adr/0026)
    entries = entries.in_fiscal_year(args[:year].to_i) if args[:year].present?
    file = Kaikeiou::SiwakeFile.new(rows: entries.map(&:to_siwake_row))
    out = args[:out].presence || "tmp/siwake_#{args[:year] || 'all'}.txt"
    File.binwrite(out, file.to_bytes)
    puts "#{out} に #{file.rows.size} 件"
  end
end

namespace :ledger do
  desc "年度初めの残高を登録する 例: bin/rails 'ledger:opening[2017,100:12000 106:345000]'"
  task :opening, [ :year, :balances ] => :environment do |_, args|
    year = Integer(args[:year])
    args[:balances].split.each do |pair|
      code, amount = pair.split(":").map { Integer(it) }
      FiscalPeriod.ensure!
      account = Account.in_year(year).find_by!(code: code)
      OpeningBalance.find_or_initialize_by(fiscal_year: year, account: account).update!(amount: amount)
      puts "#{year}年度 期首 #{account}: #{amount}"
    end
  end

  desc "年度ごとの集計"
  task summary: :environment do
    book = Ledger::Book.new
    puts %w[年度 件数 期首正味財産 収益 費用 増減 期末正味財産 整合].join("\t")
    book.statements.each do |s|
      puts [ s.fiscal_year.label, s.entries.size, s.opening_net_assets, s.revenue_total, s.expense_total,
             s.net_assets_change, s.closing_net_assets, s.balanced? ? "OK" : "NG" ].join("\t")
    end
    last = book.statements.last
    last&.closing_balances&.each { |a, v| puts "  #{last.fiscal_year.label}末 #{a}: #{v}" }
  end
end
