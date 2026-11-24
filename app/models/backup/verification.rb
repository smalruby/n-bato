# 取り出したバックアップ(storage/ と同じ並びのディレクトリ)を確かめる。
# - 各 SQLite の PRAGMA integrity_check が ok か
# - 本体の DB の active_storage_blobs のすべてに、ファイルがあり、大きさと MD5 が合うか
# 結果は件数だけ(中身は出さない)。
class Backup::Verification
  Result = Data.define(:databases, :tables, :blobs, :problems) do
    def ok? = problems.empty?
  end

  def initialize(dir)
    @dir = Pathname(dir)
  end

  def run
    problems = []
    databases = @dir.glob("*.sqlite3").sort.to_h do |db|
      status = open_db(db) { it.get_first_value("PRAGMA integrity_check") }
      problems << "#{db.basename}: integrity_check=#{status}" unless status == "ok"
      [db.basename.to_s, status]
    end
    primary = @dir.join("production.sqlite3")
    problems << "production.sqlite3 がない" unless primary.exist?
    tables, blobs = primary.exist? ? check_primary(primary, problems) : [{}, 0]
    Result.new(databases:, tables:, blobs:, problems:)
  end

  private

  def check_primary(primary, problems)
    open_db(primary) do |db|
      names = db.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name").flatten
      tables = names.to_h { [it, db.get_first_value(%(SELECT COUNT(*) FROM "#{it}"))] }
      blobs = db.execute("SELECT key, byte_size, checksum FROM active_storage_blobs WHERE service_name = 'local'")
      blobs.each { |key, size, checksum| check_blob(key, size, checksum, problems) }
      [tables, blobs.size]
    end
  end

  # SQLite3::Database.new にブロックを渡すと DB を返すので、ブロックの値を返す形にする。
  def open_db(path)
    db = SQLite3::Database.new(path.to_s, readonly: true)
    yield db
  ensure
    db&.close
  end

  def check_blob(key, size, checksum, problems)
    file = @dir.join(key[0, 2], key[2, 2], key)
    return problems << "添付 #{key}: ファイルがない" unless file.exist?
    return problems << "添付 #{key}: 大きさが違う" unless file.size == size
    problems << "添付 #{key}: MD5 が違う" unless checksum.nil? || Digest::MD5.file(file).base64digest == checksum
  end
end
