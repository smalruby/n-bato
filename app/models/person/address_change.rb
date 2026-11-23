# 住所が変わった(イベント。日付は moved_on、精度は date_precision)。docs/adr/0029
# 代表権のある理事なら、登記の事由(住所移転)もできる。打ち間違いは取り消して入れ直す(Person::ChangeCancellation)。
class Person::AddressChange < ApplicationRecord
  include EventRecord
  include Person::ChangeEvent
  event_of :moved_on, entry: :record!
  encrypts :address

  validates :address, presence: true

  def self.model_name_label = "住所の変更"

  def occurred_on = moved_on

  # 記録する(作る入口)
  def self.record!(person, address:, moved_on:, date_precision: "day", by: nil, note: "")
    person.address_changes.reset
    address = address.to_s.strip
    raise ArgumentError, "新しい住所を入れてください" if address.empty?
    raise ArgumentError, "いまの住所と同じです" if address == person.address

    transaction do
      change = create!(person:, address:, moved_on:, date_precision:, recorded_by: by, note: note.to_s)
      person.address_changes.reset
      change.send(:schedule_registration!, kind: "address_change", note: "#{person.name}の住所の変更")
      Audit.final!("#{person.name}の住所が変わった(#{change.date_label})")
      change
    end
  end
end
