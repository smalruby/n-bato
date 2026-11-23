# 年に一度の手続きの定義(config/procedures/*.yml)。手順の並び・説明・根拠の条文を持つ。
class ProcedureDefinition
  Step = Data.define(:key, :title, :guide, :law, :checks, :waits, :waits_from, :links, :deadline, :final, :optional, :effect, :done_when, :final_label, :only_when) do
    def deadline? = !!deadline
    def final? = !!final
    def optional? = !!optional

    # 「{所轄庁}」は、確認済みの提出先の名前にする(docs/adr/0027)
    %i[title guide checks waits links final_label].each do |m|
      define_method(m) { FilingDestination.fill(to_h[m]) }
    end
  end

  attr_reader :kind, :name, :period, :due, :steps

  def summary = FilingDestination.fill(@summary)

  def self.all = @all ||= Dir[Rails.root.join("config/procedures/*.yml")].sort.to_h { |f| [ File.basename(f, ".yml"), load_file(f) ] }
  def self.find(kind) = all.fetch(kind.to_s)
  def self.reload! = @all = nil

  def self.load_file(path)
    data = YAML.load_file(path)
    new(File.basename(path, ".yml"), data)
  end

  def initialize(kind, data)
    @kind = kind
    @name, @period, @due, @summary = data.values_at("name", "period", "due", "summary")
    @steps = data.fetch("steps").map do |s|
      Step.new(key: s.fetch("key"), title: s.fetch("title"), guide: Array(s["guide"]), law: Array(s["law"]),
               checks: Array(s["checks"]), waits: Array(s["waits"]), waits_from: s["waits_from"], links: Array(s["links"]),
               deadline: s["deadline"], final: s["final"], optional: s["optional"], effect: s["effect"], done_when: s["done_when"], final_label: s["final_label"], only_when: s["only_when"])
    end
  end

  def step(key) = steps.find { it.key == key.to_s }

  def due_on(period)
    case due
    when "fiscal_year_end_plus_3_months" then Date.new(period + 1, 6, 30)
    when "june_30" then Date.new(period, 6, 30)
    end
  end

  def period_label(period)
    case self.period
    when "fiscal_year" then "#{FiscalYear.new(period).wareki_label}(#{period}年度)分"
    else "#{period}年"
    end
  end
end
