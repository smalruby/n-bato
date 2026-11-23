# 氏名が変わった(イベント。日付は changed_on、精度は date_precision)。docs/adr/0029
# former_name は変わる前の氏名。show_former_name は旧氏を併記するか(商業登記規則 81 条の 2 の申出・名簿の書き方)。
class Person::NameChange < ApplicationRecord
  include EventRecord
  include Person::ChangeEvent
  event_of :changed_on, entry: :record!

  validates :name, presence: true

  def self.model_name_label = "氏名の変更"

  def occurred_on = changed_on

  # 氏と名に分ける(全角・半角の空白で区切る。区切れないときは nil)
  def self.split(full)
    parts = full.to_s.strip.split(/[\s　]+/)
    parts.size == 2 ? parts : nil
  end

  # 記録する(作る入口)
  def self.record!(person, name:, changed_on:, name_kana: nil, date_precision: "day", show_former_name: false, by: nil, note: "")
    person.name_changes.reset
    name = name.to_s.strip
    raise ArgumentError, "新しい氏名を入れてください" if name.empty?
    raise ArgumentError, "いまの氏名と同じです" if name == person.name

    transaction do
      former = person.name
      change = create!(person:, name:, name_kana: name_kana.presence || person.name_kana, former_name: former, changed_on:,
                       date_precision:, show_former_name: ActiveModel::Type::Boolean.new.cast(show_former_name) || false,
                       recorded_by: by, note: note.to_s)
      person.name_changes.reset
      change.send(:schedule_registration!, kind: "name_change", note: "#{former}の#{change.change_word}(#{name})")
      Audit.final!("#{former}の氏名が変わった(#{name}・#{change.date_label})")
      change
    end
  end

  # 「氏変更」「名変更」「氏名変更」(法務局の記載例の言葉)
  def change_word
    old_parts = self.class.split(former_name)
    new_parts = self.class.split(name)
    return "氏名変更" unless old_parts && new_parts

    if old_parts[0] != new_parts[0] && old_parts[1] == new_parts[1] then "氏変更"
    elsif old_parts[0] == new_parts[0] then "名変更"
    else "氏名変更"
    end
  end

  # 旧氏の併記。法務局の記載例は「新しい氏名（旧氏 名）」(001252649.pdf)。
  def name_with_former
    old_parts = self.class.split(former_name)
    new_parts = self.class.split(name)
    former = old_parts && new_parts ? "#{old_parts[0]}　#{new_parts[1]}" : former_name
    "#{name}（#{former}）"
  end

  def display_name = show_former_name ? name_with_former : name
end
