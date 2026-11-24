# 定款の版(デザインシステム Articles、見直し第13回)。版ごとに全文と、決めた会議・所轄庁・変わった条・理由を残す。年度に依存しない。
class ArticleVersion < ApplicationRecord
  validates :number, presence: true, uniqueness: true
  validates :decided_on, presence: true
  scope :ordered, -> { order(:number) }

  def self.current = ordered.last

  # その年度の時点の版: 年度の終わり(翌年 3 月 31 日)までに決めた版のうち、いちばん新しいもの
  def self.for_year(year)
    return current unless year

    ordered.where(decided_on: ..Date.new(year.to_i + 1, 3, 31)).last || ordered.first
  end

  def document = @document ||= Articles::Document.new(body)
  def previous = self.class.ordered.where(number: ...number).last
  def label = "版 #{number}(#{decided_on.strftime("%Y-%m-%d")} #{meeting.presence || "決定"})"

  # 前の版との違い。[[条の番号, 前の文 or nil, この版の文 or nil], …]
  def changes_from_previous
    prev = previous or return []
    before = prev.document.articles.to_h { [it.number, it.text] }
    after = document.articles.to_h { [it.number, it.text] }
    (before.keys | after.keys).sort.filter_map { |n| [n, before[n], after[n]] unless before[n] == after[n] }
  end
end
