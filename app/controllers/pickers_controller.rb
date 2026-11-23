# Picker の「すべて」を選んだときに、残りの候補も含めた一覧を返す(デザインシステム Picker)。
class PickersController < ApplicationController
  def show
    year = Current.working_year
    items = PickerItems.new(params[:source], year).all
    items.unshift({ id: "", code: "", name: "(なし)" }) if params[:source] == "departments"
    render json: { items: }
  end
end
