class AnnualReportsController < ApplicationController
  before_action :set_report, only: %i[show edit update]

  def index
    org = Organization.current
    last = FiscalYear.current.year - 1
    first = org.first_fiscal_year || last
    @reports = AnnualReport.all.index_by(&:fiscal_year)
    @years = (first..last).to_a.reverse
  end

  def show
    @statement = Ledger::Book.new.statement(@annual_report.fiscal_year)
    @expenses = @annual_report.program_expenses(@statement)
  end

  def new
    @annual_report = AnnualReport.draft_for(Integer(params[:year]))
    redirect_to annual_report_path(@annual_report.fiscal_year) if @annual_report.persisted?
  end

  # 総会で承認した日・提出した日・公告した日の欄は、変わっていれば節目のイベントとして記録する(docs/adr/0038)
  # (作るときは、まだ日付が無いので、開いたときの日付は比べない)
  def create
    attrs = report_params
    dates = attrs.extract!(*AnnualReport::FORM_DATE_COLUMNS)
    @annual_report = AnnualReport.new(attrs)
    if @annual_report.save_with_dates(dates)
      redirect_to annual_report_path(@annual_report.fiscal_year), notice: "事業報告書を作りました"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @annual_report.ensure_program_activities
  end

  def update
    attrs = report_params
    dates = attrs.extract!(*AnnualReport::FORM_DATE_COLUMNS)
    @annual_report.assign_attributes(attrs)
    # 開いたときの日付(隠した欄)と比べて、変えた欄だけ記録する。開いている間に変わっていたら断る
    opened = params[:opened_dates]&.permit(*AnnualReport::FORM_DATE_COLUMNS)
    if @annual_report.save_with_dates(dates, opened:)
      redirect_to annual_report_path(@annual_report.fiscal_year), notice: "保存しました"
    else
      flash.now[:alert] = @annual_report.errors.full_messages.join(" ").presence
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_report = @annual_report = AnnualReport.find_by!(fiscal_year: params[:year])

  def report_params
    permitted = params.require(:annual_report).permit(
      :fiscal_year, :achievements, :other_business, :board_meetings, :general_meetings, :members_note,
      :letter_date, :approved_on, :submitted_on, :bs_published_on, :bs_publication_place,
      member_counts: {}, program_activities_attributes: %i[id department_id content schedule beneficiaries report position]
    )
    if permitted[:member_counts]
      permitted[:member_counts] = permitted[:member_counts].to_h.compact_blank.transform_values(&:to_i).presence
    end
    permitted
  end
end
