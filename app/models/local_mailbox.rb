# 手元の Docker 用のメールの「受け箱」。メールを外に送らず、1 通ずつ .eml のファイルに書き出す。
# NBATO_MAIL_DELIVERY=local_mailbox のときに使う(config/environments/production.rb)。中身は bin/rails mail:latest で見る。
class LocalMailbox
  attr_accessor :settings

  def initialize(settings = {})
    @settings = settings
  end

  def location = Pathname(settings.fetch(:location))

  def deliver!(mail)
    FileUtils.mkdir_p(location)
    path = location.join("#{Time.current.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(3)}.eml")
    File.write(path, mail.to_s)
    path
  end

  # いちばん新しいメール(Mail::Message)。無ければ nil
  def self.latest(location)
    path = Dir[File.join(location, "*.eml")].max
    path && Mail.read(path)
  end

  # 表示用の本文(テキストの部分を UTF-8 で)
  def self.text_of(mail)
    part = mail.multipart? ? (mail.text_part || mail.parts.first) : mail
    part.decoded.to_s.force_encoding("UTF-8")
  end
end
