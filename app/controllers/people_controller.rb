# 会員・役員。メール・電話・メモは年度ごとの記録(操作している年度の記録を出し、直す)。
# 氏名・よみ・住所は「記録の始まり」の値で、住所・氏名が変わったときは出来事で足す(docs/adr/0029)。
# 出来事がまだ無い人だけ、記録の始まりの値を画面で直せる(打ち間違いの訂正。操作履歴に残る)。
class PeopleController < ApplicationController
  include ClosedYearGuard

  before_action :set_person, only: %i[show edit update destroy apply_to_years]

  def index
    @year = Current.working_year
    range = FiscalYear.new(@year).range
    @people = Person.ordered.includes(:memberships, :officer_terms, :person_years)
    @help_states = [:borrowed] if @people.any? { it.borrowed_year(@year) }
    @officers = OfficerTerm.includes(person: :person_years).select { it.starts_on <= range.end && (it.left_on || it.ends_on) >= range.begin }
  end

  def show
  end

  def new
    @person = Person.new
  end

  def create
    @person = Person.new(person_params)
    if @person.save
      redirect_to @person, notice: "登録しました(#{Current.working_year}年度の記録)"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  # 操作している年度の記録を直す。締めた年度は理由を書く。ほかの年度にも同じ値があれば、直すかを聞く。
  def update
    year = Current.working_year
    record = @person.year_record!(year)
    before = record.persisted? ? record.slice(*Person.year_attrs) : @person.year_values(year)
    unless closed_year_reason_ok?(year, "会員・役員の記録")
      @person.assign_attributes(start_params) unless @person.changes_recorded?
      flash.now[:alert] = @reason_needed
      return render :edit, status: :unprocessable_content
    end
    record.assign_attributes(year_params)
    @person.assign_attributes(start_params) unless @person.changes_recorded?
    if @person.save && record.save
      flash[:also] = also_years(record, before)
      redirect_to @person, notice: "#{FiscalPeriod.for(year)&.label}の記録を保存しました"
    else
      @person.errors.merge!(record.errors)
      render :edit, status: :unprocessable_content
    end
  end

  # ほかの締めていない年度の記録にも同じ値を入れる(締めた年度は、その年度に切り替えて理由を書いて直す)
  def apply_to_years
    source = @person.record_for(params[:from].to_i) or return redirect_to(@person)
    fields = Array(params[:fields]) & Person.year_attrs
    years = Array(params[:years]).map(&:to_i).reject { FiscalPeriod.for(it)&.closed? }
    Audit.label!("#{@person.name}の#{fields.map { Person.human_attribute_name(it) }.join("・")}を #{years.map { "#{it}年度" }.join("・")}にも効かせた")
    years.each do |y|
      rec = @person.year_record!(y)
      rec.update!(source.slice(*fields))
    end
    redirect_to @person, notice: "#{years.map { "#{it}年度" }.join("・")}の記録も直しました"
  end

  def destroy
    if @person.destroy
      redirect_to people_path, notice: "削除しました"
    else
      redirect_to @person, alert: @person.errors.full_messages.join(" / ")
    end
  end

  private

  def set_person = @person = Person.find(params[:id])
  def person_params = params.require(:person).permit(:name, :name_kana, :address, :email, :phone, :notes)
  def start_params = person_params.slice(:name, :name_kana, :address)
  def year_params = person_params.slice(*Person.year_attrs)

  def also_years(record, before)
    fields = Person.year_attrs.select { record.public_send(it) != before[it] }
    return nil if fields.empty?

    years = @person.year_records_list.reject { it.fiscal_year == record.fiscal_year || FiscalPeriod.for(it.fiscal_year)&.closed? }
      .select { |r| fields.any? { r.public_send(it) == before[it] } }.map(&:fiscal_year)
    years.any? ? {"from" => record.fiscal_year, "fields" => fields, "years" => years} : nil
  end
end
