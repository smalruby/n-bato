require "test_helper"

class NightlyBackupJobTest < ActiveJob::TestCase
  class FakeBackup
    attr_reader :runs

    def initialize(configured) = (@configured, @runs = configured, 0)
    def configured? = @configured

    def run!
      @runs += 1
      "n-bato/daily/2026-11-24T1900Z.tar.gz"
    end
  end

  test "S3 の設定があれば送り、無ければ飛ばす" do
    on = FakeBackup.new(true)
    NightlyBackupJob.perform_now(backup: on)
    assert_equal 1, on.runs

    off = FakeBackup.new(false)
    NightlyBackupJob.perform_now(backup: off)
    assert_equal 0, off.runs
  end

  test "S3 の設定は 3 つそろって初めて使う" do
    keys = %w[NBATO_BACKUP_BUCKET NBATO_BACKUP_AWS_ACCESS_KEY_ID NBATO_BACKUP_AWS_SECRET_ACCESS_KEY]
    with_env(keys.index_with("x")) { assert Backup.configured? }
    with_env(keys.index_with("x").merge("NBATO_BACKUP_BUCKET" => "")) { assert_not Backup.configured? }
  end
end
