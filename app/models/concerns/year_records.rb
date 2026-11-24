# 年度ごとの記録(デザインシステム「年度」: 年度ごとのデータセット)。
# ID はそのままにし、年度ごとに変わる項目を「その年度の記録」に持つ(会員・役員の Person、法人の Organization)。
# 読むときは操作している年度の記録。その年度の記録が無ければ、いちばん近い後の年度(無ければ前の年度)の記録を出す。
# 本体の列は「最新の年度の記録」の写し(並べ替え・検索用)。
module YearRecords
  extend ActiveSupport::Concern

  included do
    class_attribute :year_attrs, default: []
    class_attribute :year_records_name
  end

  class_methods do
    def year_records(name, attrs)
      self.year_records_name = name
      self.year_attrs = attrs.map(&:to_s)
      has_many name, dependent: :destroy, inverse_of: model_name.singular.to_sym
      attrs.each do |a|
        define_method(a) { (r = at) ? r.public_send(a) : read_attribute(a) }
      end
      after_create :create_first_year_record
    end
  end

  def year_records_list = public_send(year_records_name).sort_by(&:fiscal_year)
  def record_for(year) = year_records_list.find { it.fiscal_year == year }

  def at(year = Current.working_year || FiscalYear.current.year)
    list = year_records_list
    list.find { it.fiscal_year == year } || list.find { it.fiscal_year > year } || list.rfind { it.fiscal_year < year }
  end

  # その年度の記録が無く、ほかの年度の記録を出しているか
  def borrowed_year(year = Current.working_year || FiscalYear.current.year)
    r = at(year)
    r && r.fiscal_year != year ? r.fiscal_year : nil
  end

  # その年度の記録(無ければ、いま出している値を写して作る。保存はしない)
  def year_record!(year)
    record_for(year) || public_send(year_records_name).build(year_values(year).merge("fiscal_year" => year))
  end

  def year_values(year = Current.working_year || FiscalYear.current.year)
    r = at(year)
    year_attrs.index_with { r ? r.public_send(it) : read_attribute(it) }
  end

  # 最新の年度の記録を本体の列に写す(操作履歴には残さない。残るのは年度の記録の変更)
  def sync_latest!(record)
    return unless year_records_list.map(&:fiscal_year).max == record.fiscal_year

    Audit.without do
      year_attrs.each { write_attribute(it, record.public_send(it)) }
      save!(validate: false) if changed?
    end
  end

  private

  def create_first_year_record
    return if public_send(year_records_name).any?(&:persisted?)

    year = Current.working_year || FiscalYear.current.year
    Audit.without { public_send(year_records_name).create!(year_attrs.index_with { read_attribute(it) }.merge("fiscal_year" => year)) }
  end
end
