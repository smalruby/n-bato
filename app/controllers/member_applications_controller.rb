# 入会申込(デザインシステム「入会申込」)。届いた申込を見て、入会を認める・認めない。
class MemberApplicationsController < ApplicationController
  undoable_screen
  before_action :set_application, only: :show

  def index
    @applications = MemberApplication.ordered
  end

  def show
    @same = @application.same_name_people
  end

  private

  def set_application = @application = MemberApplication.find(params[:id])
end
