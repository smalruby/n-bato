# 事業ごとの主な活動(見直し第13回)。定款の事業(①〜⑨)と管理に、いまの活動を人が書いておく。年度に依存せず、部門コードで結びつける。
# 仕訳の部門選び・AI 仕訳の指示文・事業報告書の画面に出す。年に一度、事業報告の手続きで見直す。
class ProgramProfile < ApplicationRecord
  validates :code, presence: true, uniqueness: true

  def self.activities_by_code = pluck(:code, :activities).to_h.reject { |_, v| v.blank? }
  def self.for(code) = find_or_initialize_by(code: code.to_i)
end
