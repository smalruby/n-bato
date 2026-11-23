# 依頼の対話の下書きを作る。添付は PDF と画像だけ(表計算などは読めないので、PDF にしてもらう)。
module IncomingRequestMessages
  ACCEPT = %r{\A(image/(png|jpeg|gif|webp)|application/pdf)\z}

  def self.draft!(request, text, files)
    msg = request.messages.create!(role: "user", body: text, masked_body: "")
    files.each { |f| msg.files.attach(f) if f.respond_to?(:content_type) && f.content_type.to_s.match?(ACCEPT) }
    msg
  end
end
