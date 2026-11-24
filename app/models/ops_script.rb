# 運用のセッションのスクリプトを、本番の rails runner で流す(bin/prod-runner から呼ばれる)。
#
# - スクリプト全体を 1 つのトランザクションで包む(途中で止まっても半分だけ書かれない)。
# - 試し流し(apply: false)は最後に巻き戻す。ジョブは積まず、メールも送らない。
#   巻き戻らないもの: 添付ファイルの書き込み・削除、外への送信(API など)。
# - 本番流し(apply: true)は、流す前に Backup::Snapshot で本体の DB を写す。
# - スクリプトの中では `operator`(操作した人)が使える。
class OpsScript
  MAX_BYTES = 64 * 1024

  # 操作した人。本番のユーザーが 1 人のときだけ、その人。2 人以上になったら決め直す(ops-dev/0001)。
  def self.operator
    users = User.limit(2).to_a
    raise "ユーザーが #{User.count} 人いるので、operator を決められない(ops-dev で決め直す)" unless users.one?

    users.first
  end

  def self.run!(source:, name:, apply:, out: $stdout, snapshot: Backup::Snapshot.new)
    new(source:, name:, apply:, out:, snapshot:).run!
  end

  def initialize(source:, name:, apply:, out:, snapshot:)
    @source, @name, @apply, @out, @snapshot = source, name, apply, out, snapshot
  end

  def run!
    raise ArgumentError, "スクリプトが #{@source.bytesize} バイトある(#{MAX_BYTES} まで)" if @source.bytesize > MAX_BYTES

    snapshot_name = @snapshot.create! if @apply
    header(snapshot_name)
    # スクリプトの中で `operator` と書けるようにする(この rails runner のプロセスの中だけ)
    TOPLEVEL_BINDING.eval("def operator = OpsScript.operator") unless TOPLEVEL_BINDING.receiver.respond_to?(:operator, true)
    last_change = AuditChange.maximum(:id) || 0
    summary = nil
    quietly_unless_apply do
      ActiveRecord::Base.transaction do
        TOPLEVEL_BINDING.eval(@source, @name)
        summary = AuditChange.where("id > ?", last_change).group(:auditable_type, :event).count
        raise ActiveRecord::Rollback unless @apply
      end
    end
    footer(summary)
    snapshot_name
  end

  private

  def header(snapshot_name)
    @out.puts "== prod-runner: #{@apply ? "本番流し(書き込む)" : "試し流し(最後に巻き戻す)"}"
    @out.puts "== スクリプト: #{@name}"
    @out.puts "== 日時: #{Time.current.iso8601}"
    @out.puts "== 書く前のバックアップ: #{snapshot_name || "(試し流しなので取らない)"}"
    @out.puts "== 戻すとき: bin/prod-restore #{snapshot_name}" if snapshot_name
    @out.puts
  end

  def footer(summary)
    @out.puts
    @out.puts "== 操作履歴に残った変更: #{summary.values.sum} 件"
    summary.sort.each { |(type, event), count| @out.puts "==   #{type} #{event}: #{count}" }
    @out.puts "== #{@apply ? "書き込んだ" : "巻き戻した(何も書いていない)"}"
  end

  # 試し流しのときだけ、ジョブを積まず(試しの入れ物に入れる)、メールを送らない。
  def quietly_unless_apply
    return yield if @apply

    adapter, deliveries = ActiveJob::Base.queue_adapter, ActionMailer::Base.perform_deliveries
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.perform_deliveries = false
    yield
  ensure
    unless @apply
      ActiveJob::Base.queue_adapter = adapter
      ActionMailer::Base.perform_deliveries = deliveries
    end
  end
end
