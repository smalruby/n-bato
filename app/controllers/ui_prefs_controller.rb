# 画面ごとの表示の好み(説明を畳んだか など)。操作履歴には残さない。
class UiPrefsController < ApplicationController
  skip_around_action :record_operation

  def help
    screen = params.require(:screen).to_s[/\A[a-z_]{1,40}\z/] or return head(:unprocessable_entity)
    prefs = Current.user.ui_prefs.deep_dup
    (prefs["help_collapsed"] ||= {})[screen] = params[:collapsed] == "1"
    Current.user.update_column(:ui_prefs, prefs)
    head :no_content
  end
end
