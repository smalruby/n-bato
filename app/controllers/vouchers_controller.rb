class VouchersController < ApplicationController
  before_action :set_voucher, only: %i[show edit update destroy propose reject]

  def index
    # 操作している年度の証憑(日付の無いものはどの年度にも出す)
    @vouchers = Voucher.recent.includes(:journal_proposals).with_attached_files.where(issued_on: [ nil, FiscalYear.new(Current.working_year).range ])
    @ai_ready = Bookkeeper::Client.configured?
  end

  def show
    @proposals = @voucher.journal_proposals.includes(:debit_account, :credit_account, :debit_department, :credit_department).order(:id)
    @ai_ready = Bookkeeper::Client.configured?
  end

  def new
    @voucher = Voucher.new(kind: "receipt", issued_on: Date.current)
  end

  def create
    @voucher = Voucher.new(voucher_params)
    if @voucher.save
      ProposeJournalEntriesJob.perform_later(@voucher) if Bookkeeper::Client.configured? && params[:propose] == "1"
      redirect_to @voucher, notice: "証憑を登録しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @voucher.update(voucher_params)
      redirect_to @voucher, notice: "証憑を更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @voucher.journal_proposals.where(status: "approved").exists?
      redirect_to @voucher, alert: "記帳済みの提案がある証憑は削除できません"
    else
      @voucher.destroy!
      redirect_to vouchers_path, notice: "証憑を削除しました"
    end
  end

  def propose
    @voucher.update!(status: "proposing")
    ProposeJournalEntriesJob.perform_later(@voucher)
    redirect_to @voucher, notice: "AI に仕訳の提案を頼みました。少し待ってから再読み込みしてください"
  end

  def reject
    @voucher.update!(status: "rejected")
    redirect_to @voucher, notice: "この証憑は記帳しないことにしました"
  end

  private

  def set_voucher = @voucher = Voucher.find(params[:id])

  def voucher_params
    params.require(:voucher).permit(:kind, :issued_on, :amount, :description, :notes, files: [])
  end
end
