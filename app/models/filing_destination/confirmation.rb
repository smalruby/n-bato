# 提出先を人が確かめた(イベント。日時は confirmed_at)。確かめた中身の要約(digest)を残し、そのあと中身を直したら確認済みでなくなる。
class FilingDestination::Confirmation < ApplicationRecord
  include EventRecord

  event_of :confirmed_at, entry: :confirm!

  belongs_to :filing_destination
  belongs_to :confirmed_by, class_name: "User", optional: true

  def self.confirm!(destination, by:, at: Time.current)
    raise ArgumentError, "宛先(役職と氏名)か機関の名前が空です" if destination.kind == "authority" && (destination.name.blank? || destination.addressee.blank?)

    create!(filing_destination: destination, confirmed_by: by, digest: destination.digest, confirmed_at: at).tap do
      Audit.label!("提出先を確かめた: #{destination.kind_label} #{destination.name}")
    end
  end
end
