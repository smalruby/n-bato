module Kaikeiou
  # 会計王の仕訳データ(SIWAKE 3.00.00)。CP932・CRLF。
  # 1 行目: //SFD ヘッダ、2 行目: 列名、3 行目以降: 1 行 1 仕訳。
  # 読み込んだものを to_bytes すると元のバイト列に戻る。
  class SiwakeFile
    ENCODING = Encoding::Windows_31J
    EOL = "\r\n".freeze

    # [列名, 属性名, 型]
    SIDE_COLUMNS = [
      [ "科目コード", :account_code, :int ], [ "科目名称", :account_name, :str ],
      [ "補助コード", :sub_code, :int ], [ "補助科目名称", :sub_name, :str ],
      [ "部門コード", :department_code, :int ], [ "部門名称", :department_name, :str ],
      [ "課税区分コード", :tax_category_code, :int ], [ "事業分類コード", :business_category_code, :int ],
      [ "税処理コード", :tax_treatment_code, :int ], [ "税率", :tax_rate, :int ],
      [ "金額", :amount, :int ], [ "消費税", :tax_amount, :int ]
    ].freeze

    COLUMNS = (
      [ [ "伝票番号", :slip_number, :int ], [ "行番号", :line_number, :int ], [ "伝票日付", :entry_date, :date ] ] +
      SIDE_COLUMNS.map { |label, attr, type| [ "借方#{label}", :"debit_#{attr}", type ] } +
      SIDE_COLUMNS.map { |label, attr, type| [ "貸方#{label}", :"credit_#{attr}", type ] } +
      [ [ "取引摘要", :summary, :str ], [ "補助摘要", :sub_summary, :str ], [ "メモ", :memo, :str ],
        [ "付箋１", :tag1, :int ], [ "付箋２", :tag2, :int ] ]
    ).freeze

    ATTRIBUTES = COLUMNS.map { |_, attr, _| attr }.freeze
    Row = Struct.new(*ATTRIBUTES, keyword_init: true)

    DEFAULT_HEADER = {
      "FMTNAME" => "SIWAKE", "FMTVER" => "3.00.00", "APPNAME" => "n-bato", "APPVER" => "0.1.0"
    }.freeze

    class FormatError < StandardError; end

    attr_reader :header, :rows

    def self.parse(bytes)
      text = bytes.dup.force_encoding(ENCODING)
      raise FormatError, "CP932 として読めません" unless text.valid_encoding?

      text = text.encode(Encoding::UTF_8)
      lines = split_records(text)
      header_line = lines.shift or raise FormatError, "空のファイルです"
      raise FormatError, "SIWAKE のヘッダがありません" unless header_line.start_with?("//SFD ")

      columns_line = lines.shift or raise FormatError, "列名の行がありません"
      labels = parse_fields(columns_line).map(&:first)
      raise FormatError, "列が想定と違います: #{labels.inspect}" unless labels == COLUMNS.map(&:first)

      rows = lines.each_with_index.map do |line, i|
        fields = parse_fields(line)
        raise FormatError, "#{i + 3} 行目の列数が #{fields.size} です" unless fields.size == COLUMNS.size
        Row.new(**COLUMNS.zip(fields).to_h { |(_, attr, type), (value, quoted)| [ attr, cast(value, type, quoted, i + 3) ] })
      end
      new(header: parse_header(header_line), rows: rows, header_line: header_line, columns_line: columns_line)
    end

    def self.read(path) = parse(File.binread(path))

    def initialize(header: DEFAULT_HEADER, rows: [], header_line: nil, columns_line: nil)
      @header = header
      @rows = rows
      @header_line = header_line
      @columns_line = columns_line
    end

    def header_line
      @header_line || "//SFD " + header.map { |k, v| %(#{k}="#{v}") }.join(" ")
    end

    def columns_line
      @columns_line || COLUMNS.map { |label, _, _| quote(label) }.join(",")
    end

    def to_s
      ([ header_line, columns_line ] + rows.map { |row| format_row(row) }).map { |l| l + EOL }.join
    end

    def to_bytes = to_s.encode(ENCODING)

    def exported_at
      date, time = header["RTNDATE"], header["RTNTIME"]
      return unless date.present? && time.present?

      Time.zone.strptime("#{date}#{time}", "%Y%m%d%H%M%S")
    rescue ArgumentError
      nil
    end

    class << self
      private

      # 引用符の中の改行は 1 レコードの中身として扱う。
      def split_records(text)
        records = []
        buffer = +""
        text.split(EOL, -1).each do |piece|
          buffer << (buffer.empty? ? piece : EOL + piece)
          next if buffer.count('"').odd?

          records << buffer
          buffer = +""
        end
        raise FormatError, "引用符が閉じていません" unless buffer.empty?

        records.pop if records.last == ""
        records
      end

      # [値, 引用符で囲まれていたか] の配列を返す。
      def parse_fields(line)
        fields = []
        i = 0
        loop do
          if line[i] == '"'
            value = +""
            i += 1
            loop do
              j = line.index('"', i) or raise FormatError, "引用符が閉じていません: #{line}"
              value << line[i...j]
              if line[j + 1] == '"'
                value << '"'
                i = j + 2
              else
                i = j + 1
                break
              end
            end
            fields << [ value, true ]
          else
            j = line.index(",", i) || line.length
            fields << [ line[i...j], false ]
            i = j
          end
          break if i >= line.length

          raise FormatError, "区切りが不正です: #{line}" unless line[i] == ","
          i += 1
          if i == line.length
            fields << [ "", false ]
            break
          end
        end
        fields
      end

      def cast(value, type, quoted, lineno)
        case type
        when :int
          raise FormatError, "#{lineno} 行目: 数値の列が引用符で囲まれています" if quoted
          Integer(value, 10)
        when :str then value
        when :date then Wareki.parse(value)
        end
      rescue ArgumentError => e
        raise FormatError, "#{lineno} 行目: #{e.message}"
      end

      def parse_header(line)
        line.scan(/(\w+)="([^"]*)"/).to_h
      end
    end

    private

    def format_row(row)
      COLUMNS.map do |_, attr, type|
        value = row[attr]
        case type
        when :int then Integer(value).to_s
        when :str then quote(value.to_s)
        when :date then quote(Wareki.format(value))
        end
      end.join(",")
    end

    def quote(value) = %("#{value.gsub('"', '""')}")
  end
end
