# 事業年度(4/1〜3/31)。開始年で表す(2024 = 2024-04-01〜2025-03-31)。
FiscalYear = Data.define(:year) do
  def self.for(date) = new((date.month >= 4) ? date.year : date.year - 1)
  def self.current = self.for(Date.current)

  def starts_on = Date.new(year, 4, 1)
  def ends_on = Date.new(year + 1, 3, 31)
  def range = starts_on..ends_on
  def label = "#{year}年度"

  def wareki_label = if year >= 2019
                       "令和#{(year == 2019) ? "元" : year - 2018}年度"
                     else
                       "平成#{year - 1988}年度"
                     end

  def period_number(first_year: 2015) = year - first_year + 1
  def to_s = label
  def to_param = year.to_s
end
