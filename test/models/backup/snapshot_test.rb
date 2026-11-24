require "test_helper"

class Backup::SnapshotTest < ActiveSupport::TestCase
  setup do
    @storage = Pathname(Dir.mktmpdir)
    @primary = @storage.join("production.sqlite3")
    SQLite3::Database.new(@primary.to_s) { it.execute("CREATE TABLE todos (title TEXT)") }
    @snapshot = Backup::Snapshot.new(storage_dir: @storage)
  end

  teardown { FileUtils.rm_rf(@storage) }

  test "写して、日本時間の日時の名前を返し、新しい世代だけを残す" do
    names = 4.times.map { @snapshot.create!(now: Time.utc(2026, 11, 24, 9, 0, it), keep: 3) }
    assert_equal "production-20261124-180000.sqlite3", names.first
    assert_equal names.last(3), @snapshot.names
  end

  test "戻すと、写したときの中身になり、-wal・-shm は消える" do
    name = @snapshot.create!
    SQLite3::Database.new(@primary.to_s) { it.execute("INSERT INTO todos VALUES ('あとで足した')") }
    @storage.join("production.sqlite3-wal").write("x")

    @snapshot.restore!(name)
    count = SQLite3::Database.new(@primary.to_s) { |db| break db.get_first_value("SELECT COUNT(*) FROM todos") }
    assert_equal 0, count
    assert_not @storage.join("production.sqlite3-wal").exist?
  end

  test "一覧にない名前や、形の違う名前は戻さない" do
    assert_raises(ArgumentError) { @snapshot.restore!("production-20990101-000000.sqlite3") }
    assert_raises(ArgumentError) { @snapshot.restore!("../production.sqlite3") }
  end

  test "毎晩の S3 の写しに、書く前のバックアップは入れない" do
    @snapshot.create!
    out = Pathname(Dir.mktmpdir).join("b.tar.gz")
    Backup::Archive.create!(storage_dir: @storage, out_path: out.to_s)
    names = Zlib::GzipReader.open(out.to_s) { |gz| Gem::Package::TarReader.new(gz).map(&:full_name) }
    assert_equal ["production.sqlite3"], names
  end
end
