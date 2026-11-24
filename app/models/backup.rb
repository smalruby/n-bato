# 本番のデータ(storage/ の SQLite と添付ファイル)のバックアップ。
#
# - 毎晩 NightlyBackupJob が Backup.run! を呼び、1 つの tar.gz にして S3 に送る(config/recurring.yml)。
# - SQLite は動いたまま VACUUM INTO で写す(書き込みの途中を写さない)。-wal・-shm は写さない。
# - 添付ファイルは書いたら変わらないので、そのまま写す。DB を先に写すので、DB にある添付は必ず入る。
# - 戻すとき: bin/backup-fetch で手元に取り出し、bin/rails 'backup:verify[取り出した場所]' で確かめる。
module Backup
  PREFIX = "n-bato/daily/".freeze

  # S3 の置き場所の設定(環境変数)。そろっていなければ何もしない。
  def self.configured?
    %w[NBATO_BACKUP_BUCKET NBATO_BACKUP_AWS_ACCESS_KEY_ID NBATO_BACKUP_AWS_SECRET_ACCESS_KEY].all? { ENV[it].present? }
  end

  # 作って送る。送った S3 のキーを返す。
  def self.run!(storage_dir: Rails.root.join("storage"), now: Time.current, upload: nil)
    Dir.mktmpdir("n-bato-backup") do |tmp|
      path = File.join(tmp, "storage.tar.gz")
      Archive.create!(storage_dir:, out_path: path)
      (upload || Upload.new).put!(path, key: "#{PREFIX}#{now.utc.strftime('%Y-%m-%dT%H%MZ')}.tar.gz")
    end
  end
end
