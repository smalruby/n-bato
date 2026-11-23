require "test_helper"

class Kaikeiou::SiwakeImporterTest < ActiveSupport::TestCase
  setup { @bytes = file_fixture("siwake_sample.txt").binread }

  def import = Kaikeiou::SiwakeImporter.new(@bytes, filename: "siwake_sample.txt").import

  test "科目・部門・仕訳を登録する" do
    result = import
    assert result.created
    assert_equal 6, JournalEntry.count
    assert_equal "asset", Account.find_by!(code: 100).category
    assert_equal "revenue", Account.find_by!(code: 510).category
    assert_equal "program_expense", Account.find_by!(code: 658).category
    assert_equal "admin_expense", Account.find_by!(code: 730).category
    assert_equal 3, Department.find_by!(code: 113).program_number
    assert_equal [ 2024 ], JournalEntry.distinct.pluck(:fiscal_year)
  end

  test "同じファイルは 2 回取り込まない" do
    import
    result = import
    assert_not result.created
    assert_equal 6, JournalEntry.count
  end

  test "取り込んだ仕訳から元のファイルを復元できる" do
    si = import.siwake_import
    assert_equal @bytes.b, si.reload.to_siwake_file.to_bytes.b
  end
end
