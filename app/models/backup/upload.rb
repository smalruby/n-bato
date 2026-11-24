# S3 に送る・S3 から取り出す。鍵はバックアップ専用の IAM ユーザー(infra の BackupUser。n-bato/* だけ読み書きできる)。
class Backup::Upload
  REGION = "ap-northeast-1".freeze

  def initialize(client: nil, bucket: ENV.fetch("NBATO_BACKUP_BUCKET"))
    require "aws-sdk-s3"
    @bucket = bucket
    @client = client || Aws::S3::Client.new(
      region: REGION,
      access_key_id: ENV.fetch("NBATO_BACKUP_AWS_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("NBATO_BACKUP_AWS_SECRET_ACCESS_KEY")
    )
  end

  def put!(path, key:)
    File.open(path, "rb") { @client.put_object(bucket: @bucket, key:, body: it) }
    key
  end
end
