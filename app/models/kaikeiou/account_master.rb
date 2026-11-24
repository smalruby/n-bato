module Kaikeiou
  # 会計王の「勘定科目設定」「部門設定」の書き出し(CP932・CSV)を読み、科目と部門に反映する。
  #
  # 勘定科目設定: 1〜2 行目は表示設定、3 行目が列名、4 行目から科目。
  #   科目種類 0 = 仕訳に使う科目、2 = 合計行(【受取会費】など)、3 = 計算で出す行。
  #   科目性格コードで区分(資産・事業費の人件費など)が決まる。小区分の名前は、すぐ上の合計行から取る。
  # 部門設定: 1 行目が列名。部門タイプ 1 = 集計用の部門(取り込まない)。
  class AccountMaster
    Entry = Data.define(:code, :name, :short_name, :nature_code, :nature_name, :kind, :level, :group_name)

    def self.parse_accounts(bytes)
      rows = csv(bytes)
      header_index = rows.index { it.first == "勘定科目コード" } or raise SiwakeFile::FormatError, "勘定科目設定の列名の行がありません"
      columns = rows[header_index]
      col = ->(row, name) { row[columns.index(name)] }
      groups = {}
      rows.drop(header_index + 1).filter_map do |row|
        next if row.compact.empty?

        level = col.call(row, "階層レベル").to_i
        kind = col.call(row, "科目種類").to_s
        name = col.call(row, "勘定科目正式名称").to_s
        if kind == "2"
          groups[level] = name.delete("【】（）《》").strip
          groups.delete_if { |l, _| l > level }
          next
        end
        next unless kind == "0"

        Entry.new(
          code: Integer(col.call(row, "勘定科目コード")), name: name, short_name: col.call(row, "勘定科目略式名称"),
          nature_code: Integer(col.call(row, "科目性格コード")), nature_name: col.call(row, "科目性格名称"),
          kind:, level:, group_name: groups[level - 1]
        )
      end
    end

    def self.parse_departments(bytes)
      rows = csv(bytes)
      columns = rows.first
      rows.drop(1).filter_map do |row|
        next if row.compact.empty?
        next unless row[columns.index("部門タイプ")] == "0"

        {code: Integer(row[columns.index("部門コード")]), name: row[columns.index("部門略式名称")],
         full_name: row[columns.index("部門正式名称")]}
      end
    end

    def self.csv(bytes)
      CSV.parse(bytes.dup.force_encoding(Encoding::CP932).encode(Encoding::UTF_8, universal_newline: true))
    end

    # 科目を登録・更新する。SIWAKE に書かれた科目名(桁合わせの空白入り)は書き出しで元に戻すため変えない。
    # 取り込む年度: 締めていない年度すべて(締めた年度は固定する)。years で絞れる。
    def self.target_years(years = nil)
      FiscalPeriod.ensure!
      years.presence || FiscalPeriod.ordered.reject(&:closed?).map(&:year)
    end

    def self.import_accounts(bytes, years: nil)
      target_years(years).flat_map { |y| import_accounts_into(bytes, y) }
    end

    def self.import_accounts_into(bytes, year)
      parse_accounts(bytes).map do |e|
        account = Account.find_or_initialize_by(fiscal_year: year, code: e.code)
        account.name = e.name if account.new_record?
        account.full_name = Account.display_name_for(e.name)
        account.group_name = e.group_name
        account.nature_code = e.nature_code
        account.category = nil if account.will_save_change_to_nature_code?
        account.save!
        account
      end
    end

    def self.import_departments(bytes, years: nil)
      target_years(years).flat_map { |y| import_departments_into(bytes, y) }
    end

    def self.import_departments_into(bytes, year)
      parse_departments(bytes).map do |d|
        department = Department.find_or_initialize_by(fiscal_year: year, code: d[:code])
        department.name = d[:name] if department.new_record?
        department.full_name = d[:full_name]
        department.save!
        department
      end
    end
  end
end
