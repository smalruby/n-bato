require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "ログインしている人だけつなぐ" do
    session = users(:one).sessions.create!
    cookies.signed[:session_id] = session.id
    connect
    assert_equal users(:one), connection.current_user
  end

  test "ログインしていなければつながない" do
    assert_reject_connection { connect }
  end
end
