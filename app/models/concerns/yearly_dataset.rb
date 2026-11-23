# 年度ごとのデータセット(デザインシステム「年度」)。同じコードの行を年度ごとに持つ。
module YearlyDataset
  extend ActiveSupport::Concern

  included do
    validates :fiscal_year, presence: true
    validates :code, uniqueness: { scope: :fiscal_year }
    scope :in_year, ->(year) { where(fiscal_year: year) }
    before_validation { self.fiscal_year ||= Current.working_year || FiscalYear.current.year }
  end

  class_methods do
    def for_year(year, code) = in_year(year).find_by(code:)

    # 前の年度のデータセットを写して、次の年度のデータセットを作る(すでにあるコードは写さない)
    def copy_year!(from, to)
      existing = in_year(to).pluck(:code)
      in_year(from).where.not(code: existing).find_each do |row|
        create!(row.attributes.except("id", "created_at", "updated_at").merge("fiscal_year" => to))
      end
    end
  end

  # 同じコードの、別の年度の行
  def in_year(year) = year == fiscal_year ? self : self.class.for_year(year, code)
end
