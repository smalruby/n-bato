# 法人情報(年度ごとの記録)。操作している年度の記録を出し、直す。締めた年度は理由を書く。
class OrganizationsController < ApplicationController
  include ClosedYearGuard

  before_action { @organization = Organization.first_or_initialize(name: "（法人名未設定）") }

  YEAR_FIELDS = %i[name name_en address representative_title representative_name accounting_standard_note].freeze
  FIXED_FIELDS = %i[established_on first_fiscal_year].freeze

  def show
  end

  def edit
  end

  def update
    attrs = params.require(:organization).permit(*YEAR_FIELDS, *FIXED_FIELDS)
    unless closed_year_reason_ok?(Current.working_year, "法人情報")
      @organization.assign_attributes(attrs)
      flash.now[:alert] = @reason_needed
      return render :edit, status: :unprocessable_content
    end
    @organization.assign_attributes(attrs.slice(*FIXED_FIELDS))
    saved = @organization.save
    if saved
      record = @organization.year_record!(Current.working_year)
      saved = record.update(attrs.slice(*YEAR_FIELDS))
    end
    if saved
      redirect_to organization_path, notice: "#{@working_period&.label}の法人情報を保存しました"
    else
      flash.now[:alert] = (record || @organization).errors.full_messages.join(" / ")
      render :edit, status: :unprocessable_content
    end
  end
end
