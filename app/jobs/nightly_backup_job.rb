# 毎晩、本番のデータを S3 に送る(config/recurring.yml)。失敗したら例外のまま残す(Solid Queue の失敗したジョブに出る)。
class NightlyBackupJob < ApplicationJob
  # backup: テストでは偽物を渡す(本物の S3 には送らない)
  def perform(backup: Backup)
    return Rails.logger.warn("NightlyBackupJob: S3 の設定が無いので飛ばす") unless backup.configured?

    key = backup.run!
    Rails.logger.info("NightlyBackupJob: #{key} に送った")
  end
end
