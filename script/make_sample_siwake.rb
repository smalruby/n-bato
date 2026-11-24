# テスト用の架空の SIWAKE ファイルを作る(実データは使わない)。
#   bin/rails runner script/make_sample_siwake.rb
H = '//SFD FMTNAME="SIWAKE" FMTVER="3.00.00" APPNAME="会計王１８" APPVER="18.01.00" RTNDATE="20261120" RTNTIME="120000"'
C = Kaikeiou::SiwakeFile::COLUMNS.map { |l, _, _| %("#{l}") }.join(",")
def row(no, date, dc, dn, dd, ddn, cc, cn, cd, cdn, amount, summary, sub = "", memo = "")
  side = ->(code, name, dept, dname) { [code, %("#{name}"), 0, '""', dept, %("#{dname}"), 0, 0, 3, 10, amount, 0] }
  ([no, 1, %("#{date}")] + side.call(dc, dn, dd, ddn) + side.call(cc, cn, cd, cdn) +
    [%("#{summary.gsub('"', '""')}"), %("#{sub}"), %("#{memo}"), 0, 0]).join(",")
end
rows = [
  row(1, "H.36/04/06", 100, "現      金", 0, "", 500, "正会員受取会費", 900, "管理部門", 5000, "正会員受取会費", "会員A"),
  row(2, "H.36/05/11", 658, "消耗品  費(事業)", 113, "③事業", 100, "現      金", 0, "", 1200, "消耗品を買った", "ケーブル"),
  row(3, "H.36/06/01", 106, "普通  預金", 0, "", 100, "現      金", 0, "", 3000, "現金を預金に預入れ"),
  row(4, "H.36/08/20", 100, "現      金", 0, "", 510, "受取寄付金", 113, "③事業", 2000, "受取寄付金", "", "引用符\"\"を含む"),
  row(5, "H.37/02/20", 106, "普通  預金", 0, "", 550, "受取  利息", 0, "", 3, "利息"),
  row(6, "H.37/03/31", 730, "通信運搬費", 0, "", 100, "現      金", 0, "", 84, "切手", "", "1行目\r\n2行目")
]
File.binwrite("test/fixtures/files/siwake_sample.txt", ([H, C] + rows).map { it + "\r\n" }.join.encode(Encoding::Windows_31J))
puts "test/fixtures/files/siwake_sample.txt"
