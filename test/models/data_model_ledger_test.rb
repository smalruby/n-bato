require "test_helper"

# データモデルの台帳(docs/data-model.md)に、全モデルが分類つきで載っていることを確かめる(docs/adr/0002)。
class DataModelLedgerTest < ActiveSupport::TestCase
  KINDS = %w[R LE E 交差 システム].freeze

  def ledger
    @ledger ||= Rails.root.join("docs/data-model.md").read.each_line.filter_map do |line|
      cells = line.split("|").map(&:strip)
      next unless cells.size > 8 && cells[1].match?(/\A[A-Z][A-Za-z:]+\z/)

      {name: cells[1], kind: cells[3], migrated: cells[8]}
    end.index_by { it[:name] }
  end

  def models
    Rails.application.eager_load!
    ApplicationRecord.descendants.reject(&:abstract_class?)
  end

  test "全モデルが台帳に載っていて、分類が決まった記号のどれか" do
    missing = models.map(&:name) - ledger.keys
    assert_empty missing, "台帳(docs/data-model.md)に足してください"
    ledger.each_value { assert_includes KINDS, it[:kind], "#{it[:name]} の分類" }
  end

  test "台帳にあるモデルは実在する" do
    assert_empty ledger.keys - models.map(&:name)
  end

  test "EventRecord を含むモデルは、台帳で E(イベント)かつ移行済み" do
    models.select { it.include?(EventRecord) }.each do |k|
      assert_equal "E", ledger.dig(k.name, :kind), k.name
      assert_equal "済", ledger.dig(k.name, :migrated), k.name
    end
  end

  test "台帳で E かつ移行済みのモデルは EventRecord を含む" do
    ledger.each_value.select { it[:kind] == "E" && it[:migrated] == "済" }.each do |row|
      assert row[:name].constantize.include?(EventRecord), "#{row[:name]} に EventRecord を"
    end
  end
end
