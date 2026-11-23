require "test_helper"

class Kaikeiou::AccountMasterTest < ActiveSupport::TestCase
  def accounts_bytes = file_fixture("kaikeiou_accounts.txt").binread
  def departments_bytes = file_fixture("kaikeiou_departments.txt").binread

  test "仕訳に使う科目だけを読み、小区分をすぐ上の合計行から取る" do
    entries = Kaikeiou::AccountMaster.parse_accounts(accounts_bytes).index_by(&:code)
    assert_equal [ 100, 106, 220, 322, 370, 500, 501, 510, 530, 550, 600, 646, 700, 720, 730, 956, 968, 980 ], entries.keys
    assert_equal "受取会費", entries[500].group_name
    assert_equal "受取寄付金", entries[510].group_name
    assert_equal "人件費", entries[600].group_name
    assert_equal 21182, entries[720].nature_code
  end

  test "科目性格コードで区分・人件費・流動を決める" do
    Kaikeiou::AccountMaster.import_accounts(accounts_bytes)
    a = Account.where(code: [ 106, 220, 322, 370, 600, 646, 700, 720, 956, 968, 980 ]).index_by(&:code)
    assert a[106].current_asset?
    assert_not a[220].current_asset?
    assert_equal "asset", a[220].category
    assert_equal "liability", a[322].category
    assert a[322].current_liability?
    assert_not a[370].current_liability?
    assert a[600].personnel?
    assert_not a[646].personnel?
    assert a[700].personnel?
    assert_not a[720].personnel?, "720 印刷製本費は管理費のその他経費"
    assert_equal "経常外収益", a[956].activity_group
    assert_equal "経常外費用", a[968].activity_group
    assert_equal "tax", a[980].category
  end

  test "SIWAKE で先に登録した科目名(桁合わせの空白)は変えない" do
    Account.create!(code: 100, name: "現      金")
    Kaikeiou::AccountMaster.import_accounts(accounts_bytes)
    account = Account.find_by!(code: 100)
    assert_equal "現      金", account.name
    assert_equal 11110, account.nature_code
  end

  test "集計用の部門は取り込まない" do
    list = Kaikeiou::AccountMaster.import_departments(departments_bytes)
    assert_equal [ 111, 112, 900 ], list.map(&:code)
    assert_equal "管理部門", Department.find_by!(code: 900).full_name
  end

  test "勘定科目設定が無くても標準の範囲で区分する" do
    assert_equal "asset", Account.create!(code: 220, name: "什器備品").category
    assert_equal "liability", Account.create!(code: 322, name: "預り金").category
    assert_not Account.create!(code: 722, name: "会議費").personnel?
    assert Account.create!(code: 604, name: "ボランティア評価費用").personnel?
  end
end
