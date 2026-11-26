# 証憑の添付を出す(ログインした人だけ。#27)。
# Active Storage の道筋は作らない(config/application.rb の draw_routes)ので、添付はここを通してだけ出る
class Vouchers::FilesController < ApplicationController
  def show
    file = Voucher.find(params[:voucher_id]).files.find(params[:id])
    # 画像・PDF など、ブラウザで開いても安全な種類だけその場で出し、ほか(HTML・SVG など)は保存させる
    disposition = ActiveStorage.content_types_allowed_inline.include?(file.content_type) ? "inline" : "attachment"
    response.headers["Cache-Control"] = "private, no-store"
    send_data file.download, filename: file.filename.to_s, type: file.content_type, disposition:
  end
end
