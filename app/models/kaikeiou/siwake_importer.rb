module Kaikeiou
  # SIWAKE ファイルを読み込み、科目・部門・仕訳を登録する。同じファイル(SHA-256)は 2 回取り込まない。
  class SiwakeImporter
    Result = Data.define(:siwake_import, :created, :skipped_reason)

    def self.import_path(path)
      paths = File.directory?(path) ? Dir[File.join(path, "*.txt")].sort : [ path ]
      paths.map { |p| new(File.binread(p), filename: File.basename(p)).import }
    end

    def initialize(bytes, filename:)
      @bytes = bytes
      @filename = filename
    end

    def import
      sha = Digest::SHA256.hexdigest(@bytes)
      if (existing = SiwakeImport.find_by(sha256: sha))
        return Result.new(existing, false, "同じファイルを取り込み済み")
      end

      file = SiwakeFile.parse(@bytes)
      SiwakeImport.transaction do
        siwake_import = SiwakeImport.create!(
          filename: @filename, sha256: sha, header_line: file.header_line, columns_line: file.columns_line,
          format_name: file.header["FMTNAME"], format_version: file.header["FMTVER"],
          app_name: file.header["APPNAME"], app_version: file.header["APPVER"],
          exported_at: file.exported_at, entries_count: file.rows.size
        )
        # 科目・部門は年度ごとのデータセット。仕訳の日付の年度の科目・部門に付ける。
        maps = file.rows.group_by { FiscalYear.for(it.entry_date).year }.to_h do |year, rows|
          @dataset_year = year
          [ year, [ upsert_accounts(rows), upsert_departments(rows) ] ]
        end
        file.rows.each_with_index do |row, i|
          accounts, departments = maps.fetch(FiscalYear.for(row.entry_date).year)
          entry = JournalEntry.from_siwake_row(row, accounts: accounts, departments: departments)
          entry.siwake_import = siwake_import
          entry.position = i
          entry.save!
        end
        FiscalPeriod.ensure!
        FiscalPeriod.propagate_datasets!
        Result.new(siwake_import, true, nil)
      end
    end

    private

    def upsert_accounts(rows)
      pairs = rows.flat_map { |r| [ [ r.debit_account_code, r.debit_account_name ], [ r.credit_account_code, r.credit_account_name ] ] }.uniq
      pairs.to_h { |code, name| [ code, Account.find_or_create_by!(fiscal_year: @dataset_year, code: code) { |a| a.name = name } ] }
    end

    def upsert_departments(rows)
      pairs = rows.flat_map { |r| [ [ r.debit_department_code, r.debit_department_name ], [ r.credit_department_code, r.credit_department_name ] ] }
      pairs.reject { |code, _| code.zero? }.uniq.to_h { |code, name| [ code, Department.find_or_create_by!(fiscal_year: @dataset_year, code: code) { |d| d.name = name } ] }
    end
  end
end
