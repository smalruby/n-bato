require "test_helper"

# イベントの書き方の決まり(docs/adr/0003・0004)。readonly? やトリガーではなく、このテストで確かめる。
class EventRulesTest < ActiveSupport::TestCase
  WRITE_CALLS = /\.(create!?|new|insert(?:_all)?!?|upsert(?:_all)?|update(?:_all|_columns?)?!?|destroy(?:_all)?!?|delete(?:_all)?)\b/

  def event_classes
    Rails.application.eager_load!
    ApplicationRecord.descendants.reject(&:abstract_class?).select { it.include?(EventRecord) }
  end

  def app_sources
    @app_sources ||= Rails.root.glob("app/**/*.{rb,erb}").map(&:to_s).to_h { [ it, File.read(it) ] }
  end

  test "イベントのクラスがある" do
    assert_operator event_classes.size, :>=, 4
  end

  test "日時の列は宣言した 1 つ。created_at・updated_at は持たない" do
    event_classes.each do |k|
      assert k.event_time_column, "#{k.name}: event_of で日時の列を宣言する"
      assert_includes k.column_names, k.event_time_column, k.name
      assert_includes %i[datetime date], k.columns_hash[k.event_time_column].type, k.name
      assert_empty k.column_names & %w[created_at updated_at], "#{k.name}: イベントに created_at・updated_at は付けない"
    end
  end

  test "作る入口は宣言どおりにある" do
    event_classes.each { assert_respond_to it, it.event_entry_point, it.name }
  end

  test "アプリのコードから、イベントを直接作ったり書き換えたり消したりしない(作るのは入口だけ)" do
    event_classes.each do |k|
      own = Rails.root.join("app/models/#{k.name.underscore}.rb").to_s
      pattern = /(?<![\w:])#{Regexp.escape(k.name)}#{WRITE_CALLS.source}/
      offenders = app_sources.reject { |path, _| path == own }.select { |_, src| src.match?(pattern) }.keys
      assert_empty offenders, "#{k.name} は #{k.event_entry_point} から作る"
    end
  end

  test "アプリのコードから、提案の詳細のイベントを書き換えたり消したりしない" do
    offenders = app_sources.select { |_, src| src.match?(/\.(approval|rejection|withdrawal)\.(update|destroy|delete)/) }.keys
    assert_empty offenders
  end
end
