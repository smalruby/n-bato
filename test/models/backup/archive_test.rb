require "test_helper"
require "aws-sdk-s3"

class Backup::ArchiveTest < ActiveSupport::TestCase
  setup do
    @tmp = Pathname(Dir.mktmpdir)
    @storage = @tmp.join("storage").tap(&:mkpath)
    @blob = "abcdefghijkl"
    @content = "架空の添付ファイル"
    @storage.join("ab/cd").mkpath
    @storage.join("ab/cd/#{@blob}").write(@content)
    SQLite3::Database.new(@storage.join("production.sqlite3").to_s) do |db|
      db.execute("PRAGMA journal_mode = WAL")
      db.execute("CREATE TABLE active_storage_blobs (key TEXT, byte_size INTEGER, checksum TEXT, service_name TEXT)")
      db.execute("CREATE TABLE todos (title TEXT)")
      db.execute("INSERT INTO todos VALUES ('a'), ('b')")
      db.execute("INSERT INTO active_storage_blobs VALUES (?, ?, ?, 'local')",
        [@blob, @content.bytesize, Digest::MD5.base64digest(@content)])
    end
    SQLite3::Database.new(@storage.join("production_queue.sqlite3").to_s) { it.execute("CREATE TABLE q (id INTEGER)") }
  end

  teardown { FileUtils.rm_rf(@tmp) }

  test "storage を固めて広げると、DB と添付がそろい、確かめが通る" do
    restored = archive_and_extract
    assert_equal %w[ab/cd/abcdefghijkl production.sqlite3 production_queue.sqlite3],
      restored.glob("**/*").select(&:file?).map { it.relative_path_from(restored).to_s }.sort

    result = Backup::Verification.new(restored).run
    assert result.ok?, result.problems.inspect
    assert_equal({"production.sqlite3" => "ok", "production_queue.sqlite3" => "ok"}, result.databases)
    assert_equal 2, result.tables["todos"]
    assert_equal 1, result.blobs
  end

  test "添付が欠けている・中身が違うと、確かめで見つかる" do
    restored = archive_and_extract
    restored.join("ab/cd/#{@blob}").write("別の中身の添付ファイル!")
    result = Backup::Verification.new(restored).run
    assert_not result.ok?
    assert_match "大きさが違う", result.problems.join

    restored.join("ab/cd/#{@blob}").delete
    assert_match "ファイルがない", Backup::Verification.new(restored).run.problems.join
  end

  test "Backup.run! は日時の名前で S3 に送る" do
    client = Aws::S3::Client.new(stub_responses: true)
    sent = []
    client.stub_responses(:put_object, ->(context) {
      sent << context.params.slice(:bucket, :key)
      {}
    })
    upload = Backup::Upload.new(client:, bucket: "example-bucket")

    key = Backup.run!(storage_dir: @storage, now: Time.utc(2026, 11, 24, 19, 0), upload:)
    assert_equal "n-bato/daily/2026-11-24T1900Z.tar.gz", key
    assert_equal [{bucket: "example-bucket", key: "n-bato/daily/2026-11-24T1900Z.tar.gz"}], sent
  end

  private

  def archive_and_extract
    out = @tmp.join("storage.tar.gz")
    Backup::Archive.create!(storage_dir: @storage, out_path: out.to_s)
    @tmp.join("restored").tap do |dir|
      dir.mkpath
      system("tar", "-xzf", out.to_s, "-C", dir.to_s, exception: true)
    end
  end
end
