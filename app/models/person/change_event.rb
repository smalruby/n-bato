# 住所の変更・改姓の出来事に共通のこと(日付の精度・取消・登記の事由)。docs/adr/0029
module Person::ChangeEvent
  extend ActiveSupport::Concern

  # 日の分かり方。日が分からないときは、分かっている範囲の初めの日(月の 1 日・年度の 4/1)を入れ、推測で日を埋めない。
  PRECISIONS = { "day" => "日まで分かる", "month" => "月まで(日は不明)", "fiscal_year" => "年度まで(日は不明)" }.freeze

  included do
    belongs_to :person
    belongs_to :recorded_by, class_name: "User", optional: true
    has_one :cancellation, as: :change, class_name: "Person::ChangeCancellation", dependent: :restrict_with_error
    has_one :registration, foreign_key: "person_#{name.demodulize.underscore}_id", dependent: :restrict_with_error, inverse_of: false
    validates :date_precision, inclusion: { in: PRECISIONS.keys }
  end

  class_methods do
    # 画面の「日付」欄の入れ方(年・月・日 / 年・月)から、日付と精度を作る
    def parse_date(year:, month:, day: nil)
      y = Integer(year.to_s, exception: false)
      m = Integer(month.to_s, exception: false)
      raise ArgumentError, "年と月を入れてください" unless y && m && (1..12).cover?(m)

      d = Integer(day.to_s, exception: false)
      return [ Date.new(y, m, 1), "month" ] if d.nil?

      [ Date.new(y, m, d), "day" ]
    rescue Date::Error
      raise ArgumentError, "その日付はありません"
    end
  end

  def cancelled? = cancellation.present?
  def day_known? = date_precision == "day"

  def date_label
    case date_precision
    when "day" then occurred_on.strftime("%Y/%m/%d")
    when "month" then "#{occurred_on.strftime('%Y/%m')}(日は不明)"
    else "#{FiscalYear.for(occurred_on).year}年度のうち(日は不明)"
    end
  end

  private

  # 代表権のある理事(登記されている役員)の住所・氏名が変わったら、登記の事由を作る(2 週間以内。日が不明なら期限も不明)
  def schedule_registration!(kind:, note:)
    term = person.officer_terms.select { it.representative? && it.serving_on?(occurred_on) }.max_by(&:starts_on)
    return unless term

    Registration.create!(kind:, cause_on: occurred_on, due_on: day_known? ? occurred_on + Registration::DEADLINE_DAYS : nil,
                         officer_term: term, note:, "person_#{self.class.name.demodulize.underscore}" => self)
  end
end
