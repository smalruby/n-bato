ENV["RAILS_ENV"] ||= "test"

# カバレッジ: COVERAGE=1 bin/rails test。測り始めるのは test/simplecov_start.rb(ruby -Itest で直接流すときのため、ここでも読む)
require_relative "simplecov_start" if ENV["COVERAGE"]
require_relative "../config/environment"
require "rails/test_help"

# 自動テストでは Chrome を立ち上げない。PDF は偽物で作り、渡した HTML を確かめる(app/models/pdf_renderer.rb)
PdfRenderer.engine = PdfRenderer::Fake

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    setup { PdfRenderer::Fake.reset! }

    # Add more helper methods to be used by all tests here...

    # 事業報告を作り、承認・提出などの日付を節目のイベントで入れる(docs/adr/0038)。操作履歴には残さない(テストの準備)
    def create_annual_report!(fiscal_year, **dates)
      Audit.without do
        report = AnnualReport.find_or_create_by!(fiscal_year:)
        dates.each { |column, on| AnnualReport::Milestone.record!(report, AnnualReport::Milestone.kind_for(column), on:) }
        report.reload
      end
    end

    # 環境変数を一時的に変える(nil は消す)。テストの後は元に戻す
    def with_env(vars)
      before = vars.keys.to_h { [ it, ENV[it] ] }
      vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      yield
    ensure
      before.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    # Claude API を偽物にして、鍵があることにする。答えは呼ばれた順(最後の答えはくり返す)
    def with_fake_claude(*replies)
      api = FakeClaudeApi.new(*replies)
      before = Bookkeeper::Client.api
      Bookkeeper::Client.api = api
      with_env("ANTHROPIC_API_KEY" => "test-key") { yield api }
    ensure
      Bookkeeper::Client.api = before
    end
  end
end

# Claude API(Anthropic::Client)の偽物。答えは Hash(JSON にして返す)・文字・Message・例外。本物の API は呼ばない
class FakeClaudeApi
  Block = Data.define(:type, :text)
  Message = Data.define(:stop_reason, :content)

  attr_reader :requests

  def self.reply(text, stop_reason: :end_turn) = Message.new(stop_reason, [ Block.new(:text, text), Block.new(:thinking, "") ])

  def initialize(*replies) = (@replies, @requests = replies, [])
  def messages = self

  def create(**params)
    @requests << params
    r = @replies.size > 1 ? @replies.shift : @replies.first
    raise r if r.is_a?(Exception)

    r.is_a?(Message) ? r : self.class.reply(r.is_a?(String) ? r : r.to_json)
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

  # PDF(ヘッドレス Chrome で作る)を出せることを確かめる。Chrome が無い機械では skip(テストの最後で呼ぶ)
  def assert_pdf(path)
    get path
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
  end
end
