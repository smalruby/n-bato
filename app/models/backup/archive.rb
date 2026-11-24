require "rubygems/package"

# storage/ を 1 つの tar.gz にする。中身は storage/ と同じ並び(戻すときは、そのまま storage/ に広げる)。
class Backup::Archive
  SQLITE = /\.sqlite3\z/
  SKIP = /\.sqlite3-(wal|shm|journal)\z/

  def self.create!(storage_dir:, out_path:)
    new(Pathname(storage_dir)).write(out_path)
  end

  def initialize(storage_dir)
    @storage_dir = storage_dir
  end

  def write(out_path)
    Dir.mktmpdir("n-bato-sqlite") do |tmp|
      snapshots = snapshot_databases(tmp)
      Zlib::GzipWriter.open(out_path) do |gz|
        Gem::Package::TarWriter.new(gz) do |tar|
          snapshots.each { |name, path| add_file(tar, name, path) }
          plain_files.each { |name| add_file(tar, name, @storage_dir.join(name)) }
        end
      end
    end
    out_path
  end

  private

  # storage/ の直下の *.sqlite3 を、VACUUM INTO で一時の場所に写す。{ 名前 => 写しの場所 }
  def snapshot_databases(tmp)
    @storage_dir.glob("*.sqlite3").sort.to_h do |db|
      copy = File.join(tmp, db.basename.to_s)
      SQLite3::Database.new(db.to_s, readonly: true) { it.execute("VACUUM INTO ?", [ copy ]) }
      [ db.basename.to_s, copy ]
    end
  end

  # DB 以外のファイル(添付ファイルなど)。storage/ からの相対の名前。
  def plain_files
    @storage_dir.glob("**/*", File::FNM_DOTMATCH).select(&:file?).filter_map do |file|
      name = file.relative_path_from(@storage_dir).to_s
      next if name.match?(SKIP)
      next if name.start_with?("#{Backup::Snapshot::DIR}/") # 書く前のバックアップは送らない
      next if !name.include?("/") && name.match?(SQLITE)

      name
    end.sort
  end

  def add_file(tar, name, path)
    stat = File.stat(path)
    tar.add_file_simple(name, 0o644, stat.size) do |io|
      File.open(path, "rb") { IO.copy_stream(it, io) }
    end
  end
end
