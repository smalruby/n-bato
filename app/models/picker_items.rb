# Picker(一覧から選んで入れるセル)の候補(デザインシステム Picker)。
# 最初は、これまでの仕訳で使った科目・部門だけを画面に入れる。残りは「すべて」を選んだときに別に取りに来る(PickersController)。
# 年度をまたいでは、コードで同じ科目・部門とみなす。
class PickerItems
  SOURCES = %w[accounts departments].freeze

  def initialize(source, year)
    raise ArgumentError, source unless SOURCES.include?(source)

    @source, @year = source, year
  end

  def all = scope.map { item(it) }

  def used
    codes = used_codes
    scope.select { codes.include?(it.code) }.map { item(it) }
  end

  def total = scope.size

  private

  def model = (@source == "accounts") ? Account : Department

  def scope
    @scope ||= begin
      s = model.in_year(@year).ordered
      s = s.where.not(category: "special") if model == Account
      s.to_a
    end
  end

  def used_codes
    ids = %w[debit credit].flat_map { JournalEntry.distinct.pluck(:"#{it}_#{model.model_name.singular}_id") }.compact.uniq
    model.where(id: ids).distinct.pluck(:code).to_set
  end

  # 部門には、事業ごとの主な活動(定款と事業)を添える。探す語にも入る。
  def item(r)
    h = {id: r.id, code: r.code.to_s, name: r.display_name}
    h[:hint] = hints[r.code] if model == Department && hints[r.code]
    h
  end

  def hints = @hints ||= ProgramProfile.activities_by_code
end
