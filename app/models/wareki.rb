# 和暦の日付(所轄庁・法務局の様式に合わせる)。画面では ApplicationHelper#wareki_date から使う。
module Wareki
  module_function

  def date(date, zen: false)
    return "" unless date

    era, base = date >= Date.new(2019, 5, 1) ? [ "令和", 2018 ] : [ "平成", 1988 ]
    y = date.year - base
    text = "#{era}#{y == 1 ? '元' : y}年#{date.month}月#{date.day}日"
    zen ? zenkaku(text) : text
  end

  # 数字を全角にする
  def zenkaku(text) = text.to_s.tr("0-9", "０-９")
end
