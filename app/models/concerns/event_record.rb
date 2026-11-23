# イベント(業務の出来事)の印。docs/adr/0002〜0004。
#
# - 日時は、出来事の名前の付いた列を 1 つだけ持つ(created_at・updated_at は持たない)。
# - 追加するだけ。アプリのコードから書き換え・消しはしない(訂正は取り消しや訂正のイベントを足す)。
# - 作る入口は、クラスメソッド 1 つだけ(名前は出来事に合う動詞。迷ったら record!)。
#
# 守り方は設計とテスト(test/models/event_rules_test.rb)。readonly? やデータベースのトリガーでは止めない
# (マイグレーションや保守のタスクから直せるようにするため。docs/adr/0003)。
module EventRecord
  extend ActiveSupport::Concern

  class_methods do
    # event_of :approved_at, entry: :approve!
    def event_of(time_column, entry:)
      @event_time_column = time_column.to_s
      @event_entry_point = entry.to_sym
    end

    def event_time_column = @event_time_column
    def event_entry_point = @event_entry_point
  end

  def occurred_at = self[self.class.event_time_column]
end
