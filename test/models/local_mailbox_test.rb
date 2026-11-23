require "test_helper"

class LocalMailboxTest < ActiveSupport::TestCase
  test "メールを 1 通ずつ書き出し、いちばん新しいものの本文を日本語で読める" do
    Dir.mktmpdir do |dir|
      box = LocalMailbox.new(location: dir)
      assert_nil LocalMailbox.latest(dir)
      mail = PasswordsMailer.reset(users(:one)).message
      box.deliver!(mail)
      latest = LocalMailbox.latest(dir)
      assert_equal "Nばと: パスワードを決め直すリンク", latest.subject
      assert_match "/passwords/", LocalMailbox.text_of(latest)
      assert_match "15 分", LocalMailbox.text_of(latest)
    end
  end
end
