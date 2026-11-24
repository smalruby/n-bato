require "test_helper"

class Kaikeiou::SiwakeFileTest < ActiveSupport::TestCase
  setup { @bytes = file_fixture("siwake_sample.txt").binread }

  test "読み込んで書き出すと元と同じバイト列になる" do
    file = Kaikeiou::SiwakeFile.parse(@bytes)
    assert_equal 6, file.rows.size
    assert_equal @bytes.b, file.to_bytes.b
  end

  test "各列を型どおりに読む" do
    file = Kaikeiou::SiwakeFile.parse(@bytes)
    row = file.rows[1]
    assert_equal Date.new(2024, 5, 11), row.entry_date
    assert_equal 658, row.debit_account_code
    assert_equal "消耗品  費(事業)", row.debit_account_name
    assert_equal 113, row.debit_department_code
    assert_equal 1200, row.credit_amount
    assert_equal "SIWAKE", file.header["FMTNAME"]
    assert_equal "会計王１８", file.header["APPNAME"]
    assert_equal Time.zone.local(2026, 11, 20, 12, 0, 0), file.exported_at
  end

  test "引用符と改行を含む文字列" do
    rows = Kaikeiou::SiwakeFile.parse(@bytes).rows
    assert_equal %(引用符"を含む), rows[3].memo
    assert_equal "1行目\r\n2行目", rows[5].memo
  end

  test "新しく作ったファイルは既定のヘッダを持ち、読み戻せる" do
    rows = Kaikeiou::SiwakeFile.parse(@bytes).rows
    bytes = Kaikeiou::SiwakeFile.new(rows: rows).to_bytes
    assert bytes.start_with?('//SFD FMTNAME="SIWAKE" FMTVER="3.00.00"'.encode(Encoding::Windows_31J))
    assert_equal rows, Kaikeiou::SiwakeFile.parse(bytes).rows
  end

  test "形式が違うとエラー" do
    assert_raises(Kaikeiou::SiwakeFile::FormatError) { Kaikeiou::SiwakeFile.parse("a,b\r\n") }
    broken = @bytes.b.sub("H.36/05/11".encode(Encoding::Windows_31J).b, "2024/05/11")
    assert_raises(Kaikeiou::SiwakeFile::FormatError) { Kaikeiou::SiwakeFile.parse(broken) }
  end

  test "書き出した日時が読めなければ nil" do
    assert_nil Kaikeiou::SiwakeFile.new(header: {"RTNDATE" => "20261399", "RTNTIME" => "120000"}).exported_at
    assert_nil Kaikeiou::SiwakeFile.new.exported_at
  end

  test "行の終わりのカンマのあとは空の列" do
    assert_equal [["1", false], ["", false]], Kaikeiou::SiwakeFile.send(:parse_fields, "1,")
  end
end
