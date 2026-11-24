# 毎晩、本番のデータを S3 に送る(config/recurring.yml)。失敗したら例外のまま残す(Solid Queue の失敗したジョブに出る)。
class NightlyBackupJob < ApplicationJob
  def perform
    return Rails.logger.warn("NightlyBackupJob: S3 の設定が無いので飛ばす") unless Backup.configured?

    key = Backup.run!
    Rails.logger.info("NightlyBackupJob: #{key} に送った")
  end
end
