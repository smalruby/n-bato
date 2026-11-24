# 書く前のバックアップ: 本番の本体の DB(production.sqlite3)を、同じサーバーの storage/backups/ に写す。
# 運用のスクリプトで間違えたときにすぐ戻すためのもの(サーバーごと失ったときは S3 とスナップショットから戻す)。
# storage/backups/ は毎晩の S3 の写しに入れない(Backup::Archive)。
class Backup::Snapshot
  DIR = "backups".freeze
  KEEP = 20
  NAME = /\Aproduction-\d{8}-\d{6}\.sqlite3\z/
  PRIMARY = "production.sqlite3".freeze

  def initialize(storage_dir: Rails.root.join("storage"))
    @storage_dir = Pathname(storage_dir)
    @dir = @storage_dir.join(DIR)
  end

  # 写して、写しの名前を返す。新しい KEEP 世代より古いものは消す。
  def create!(now: Time.current, keep: KEEP)
    @dir.mkpath
    name = "production-#{now.in_time_zone("Tokyo").strftime("%Y%m%d-%H%M%S")}.sqlite3"
    path = @dir.join(name)
    raise ArgumentError, "#{name} はもうある" if path.exist?

    db = SQLite3::Database.new(@storage_dir.join(PRIMARY).to_s, readonly: true)
    db.execute("VACUUM INTO ?", [path.to_s])
    db.close
    names.reverse.drop(keep).each { @dir.join(it).delete }
    name
  end

  def names = @dir.exist? ? @dir.children.map { it.basename.to_s }.grep(NAME).sort : []

  # 写しを本体の DB に戻す。アプリを止めてから呼ぶ(bin/prod-restore)。
  def restore!(name)
    raise ArgumentError, "名前が違う: #{name}" unless name.match?(NAME) && names.include?(name)

    target = @storage_dir.join(PRIMARY)
    tmp = @storage_dir.join("#{PRIMARY}.restoring")
    FileUtils.cp(@dir.join(name), tmp)
    %w[-wal -shm].each { FileUtils.rm_f("#{target}#{it}") }
    File.rename(tmp, target)
    name
  end
end
