ENV["RAILS_ENV"] ||= "test"

# カバレッジ: COVERAGE=1 bin/rails test(結果は coverage/。git 管理外)。対象はバックエンドのコード(ビューと JavaScript は対象外。docs/adr/0025)
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    add_filter %w[/test/ /config/ /db/ /vendor/ /lib/tasks/ /app/views/ /app/javascript/ /app/assets/]
  end
end
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)
    if ENV["COVERAGE"]
      parallelize_setup { |worker| SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}" }
      parallelize_teardown { SimpleCov.result }
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

module SignInHelper
  def sign_in(user = users(:one))
    post session_path, params: { email_address: user.email_address, password: "password" }
    assert_response :redirect
  end

  # 法人が無いとホームは最初の起動のウィザードへ移る(見直し第17回)。ホームを開くテストで使う
  def ensure_organization = Organization.first || Organization.create!(name: "テスト法人", first_fiscal_year: 2023)

  def import_sample
    Kaikeiou::SiwakeImporter.new(file_fixture("siwake_sample.txt").binread, filename: "siwake_sample.txt").import
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper
end
