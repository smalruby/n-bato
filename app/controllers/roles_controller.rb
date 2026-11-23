# いま使う役割を切り替える(デザインシステム「役割」)。切り替えられる役割は利用者ごとに決まっている。
# 監査の役割で使っていても切り替えられるよう、閲覧だけの制限から外す(READ_ONLY_ALLOWED)。
class RolesController < ApplicationController
  skip_around_action :record_operation

  def update
    role = params.require(:role).to_s
    return redirect_back(fallback_location: root_path, alert: "その役割には切り替えられません") unless Current.user.can_use?(role)

    Current.user.update!(role:)
    redirect_back fallback_location: root_path, notice: "#{Current.user.role_label}として使います"
  end
end
