# 役員が退任した(イベント。日付は left_on)。1 つの任期に 1 回。任期の満了(ends_on)とは別の、任期の途中の退任。docs/adr/0030
# 元に戻せない操作。いまは記録する画面が無く、data:load や運用のスクリプトから記録する(画面は見直し票で決めてから)。
class OfficerTerm::Resignation < ApplicationRecord
  include EventRecord

  event_of :left_on, entry: :resign!

  belongs_to :officer_term
  belongs_to :recorder, class_name: "User", optional: true

  validates :left_on, presence: true

  def audit_fiscal_year = left_on && FiscalYear.for(left_on).year

  # 記録する(作る入口)。by: は人が画面から記録するときに渡す(rake・AI からは省ける)。
  def self.resign!(term, left_on:, reason: "", by: nil)
    left_on = ActiveModel::Type::Date.new.cast(left_on)
    raise ArgumentError, "退任した日を入れてください" unless left_on
    raise ArgumentError, "退任した日は就任日より後にしてください" if left_on < term.starts_on
    raise ArgumentError, "この任期は、もう退任の記録があります" if exists?(officer_term: term)

    transaction do
      resignation = create!(officer_term: term, left_on:, reason: reason.to_s.strip, recorder: by)
      term.reset_resignation
      Audit.final!("#{term.person.name}さんが#{term.role_label}を退任した(#{I18n.l(left_on)})")
      resignation
    end
  end
end
