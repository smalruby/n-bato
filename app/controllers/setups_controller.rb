# 最初の起動のウィザード(見直し第17回): ①法人の名前と所在地 ②提出先を AI に調べてもらう ③人が確かめる ④できあがり。
class SetupsController < ApplicationController
  STEPS = {1 => "法人の名前と所在地", 2 => "提出先の案(AI が調べる)", 3 => "人が確かめる", 4 => "できあがり"}.freeze

  def show
    @step = params[:step].to_i.clamp(1, 4)
    @step = 1 if Organization.none?
    @organization = Organization.first || Organization.new
    @search = FilingDestinationSearch.latest
    @destinations = FilingDestination.ordered.includes(:confirmations)
    @ai_ready = Bookkeeper::Client.configured?
  end

  def update
    name = params[:name].to_s.strip
    address = params[:address].to_s.strip
    return redirect_to(setup_path(step: 1), alert: "法人の名前と所在地を入れてください") if name.blank? || address.blank?

    org = Organization.first_or_initialize
    org.update!(name:, first_fiscal_year: org.first_fiscal_year || FiscalYear.current.year)
    org.year_record!(Current.working_year || FiscalYear.current.year).update!(name:, address:)
    Audit.label!("最初の起動: 法人の名前と所在地を入れた")
    redirect_to setup_path(step: 2)
  end

  private

  def audit_scope = "organization"
end
