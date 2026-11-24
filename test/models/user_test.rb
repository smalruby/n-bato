require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "役割は決まったものだけを持つ" do
    user = users(:two)
    user.roles = [ :auditor, "unknown", "clerk" ]
    assert_equal "auditor,clerk", user.allowed_roles
    assert_equal %w[auditor clerk], user.roles
    user.roles = nil
    assert_equal [], user.roles
  end
end
