class ResolutionsController < ApplicationController
  before_action :set_resolution, only: %i[show edit update destroy document apply_item]

  DOCUMENTS = { "proposal" => "提案書", "consent_form" => "同意書", "minutes" => "議事録" }.freeze

  def index
    @resolutions = ::Resolution.recent.includes(:items, :consents).where(proposed_on: FiscalYear.new(Current.working_year).range)
  end

  def show
    @voters = @resolution.voters
    @consents = @resolution.consents.includes(:person).index_by(&:person_id)
  end

  def new
    @resolution = ::Resolution.new(body: params[:body].presence_in(::Resolution::BODIES.keys) || "general_meeting", voting_method: "written", proposed_on: Date.current,
                                 proposer: OfficerTerm.serving_on(Date.current).find { it.role == "chair" }&.person)
    3.times { |i| @resolution.items.build(position: i) }
  end

  def create
    @resolution = ::Resolution.new(resolution_params)
    if @resolution.save
      redirect_to @resolution, notice: "決議の提案を作りました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @resolution.items.build(position: @resolution.items.size)
  end

  def update
    if @resolution.update(resolution_params)
      redirect_to @resolution, notice: "保存しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @resolution.destroy!
    redirect_to resolutions_path, notice: "削除しました"
  end

  def document
    @doc = DOCUMENTS.keys.find { it == params[:doc] } or raise ActionController::RoutingError, "unknown document"
    @title = DOCUMENTS[@doc]
    @organization = Organization.current
    respond_to do |format|
      format.html { render "resolutions/document", layout: "print" }
      # :nocov: PDF はヘッドレス Chrome で作る(機械に依存するので、テストでは HTML を確かめる。PdfRenderer は計算書類の画面のテストで通す)
      format.pdf do
        @pdf = true
        html = render_to_string("resolutions/document", layout: "print", formats: [ :html ])
        send_data PdfRenderer.render(html), filename: "resolution-#{@resolution.id}-#{@doc}.pdf", type: "application/pdf", disposition: "inline"
      end
      # :nocov:
    end
  end

  def apply_item
    item = @resolution.items.find(params[:item_id])
    item.apply!
    redirect_to @resolution, notice: "「#{item.title}」を記録に反映しました"
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, RuntimeError => e
    redirect_to @resolution, alert: e.message
  end

  private

  def set_resolution = @resolution = ::Resolution.find(params[:id])

  def resolution_params
    params.require(:resolution).permit(:body, :title, :proposed_on, :proposer_id, :voting_method, :held_on, :place, :note, :minutes_author_id,
                                       items_attributes: %i[id position kind title content appointments_text fiscal_year _destroy])
  end
end
