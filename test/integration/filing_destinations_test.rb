require "test_helper"

# 設定 › 提出先と、最初の起動のウィザード(見直し第17回)
class FilingDestinationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { ensure_organization; sign_in }

  test "足す・直す(すぐ保存)・確かめる・消す" do
    post filing_destinations_path, params: { kind: "authority" }
    d = FilingDestination.last
    assert_redirected_to filing_destinations_path(anchor: "dest-#{d.id}")

    patch filing_destination_path(d, format: :json), params: { filing_destination: { name: "テスト市", addressee: "テスト市長　山田　太郎" } }
    assert response.parsed_body["ok"]
    assert_equal "テスト市長　山田　太郎", d.reload.addressee

    get filing_destinations_path
    assert_select "tr#dest-#{d.id}", text: /まだ確かめていない/
    assert_select "a[href=?]", filing_samples_path(format: :pdf)

    post filing_destination_confirmation_path(d)
    assert d.reload.confirmed?
    get filing_destinations_path
    assert_select "tr#dest-#{d.id} .nb-dest-state.is-confirmed"

    delete filing_destination_path(d)
    assert_not FilingDestination.exists?(d.id)
  end

  test "所轄庁の名前か宛先が空なら確認済みにできない" do
    d = FilingDestination.create!(kind: "authority", name: "テスト市")
    post filing_destination_confirmation_path(d)
    assert_match "宛先", flash[:alert]
  end

  test "AI の鍵が無ければ調べものを頼まない。鍵があれば裏の仕事に回し、待つ表示を出す" do
    with_key(nil) do
      post filing_destination_searches_path
      assert_match "AI の鍵", flash[:alert]
    end
    Organization.first.year_record!(Current.working_year || FiscalYear.current.year).update!(name: "テスト法人", address: "テスト県テスト市1-1")
    with_key("sk-test") do
      assert_enqueued_with(job: FilingDestinationSearchJob) { post filing_destination_searches_path }
      get filing_destinations_path
      assert_select ".nb-waiting[data-controller=auto-reload]"
    end
  end

  def with_key(value)
    before = ENV["ANTHROPIC_API_KEY"]
    value ? ENV["ANTHROPIC_API_KEY"] = value : ENV.delete("ANTHROPIC_API_KEY")
    skip "credentials に鍵がある環境では確かめない" if value.nil? && Bookkeeper::Client.configured?
    yield
  ensure
    before ? ENV["ANTHROPIC_API_KEY"] = before : ENV.delete("ANTHROPIC_API_KEY")
  end

  test "様式の例: 架空の法人で一式を出す(宛先も例)" do
    get filing_samples_path
    assert_response :success
    assert_match "（例）NPO法人サンプル", response.body
    assert_match "（例）○○市長", response.body
  end

  test "最初の起動: 法人が無ければホームからウィザードへ。名前と所在地を入れて進む" do
    OrganizationYear.delete_all
    Organization.delete_all
    get root_path
    assert_redirected_to setup_path
    get setup_path
    assert_select ".nb-setup h1", "法人の名前と所在地"
    patch setup_path, params: { name: "テスト法人", address: "" }
    assert_redirected_to setup_path(step: 1)
    patch setup_path, params: { name: "テスト法人", address: "テスト県テスト市1-1" }
    assert_redirected_to setup_path(step: 2)
    assert_equal "テスト県テスト市1-1", Organization.first.address
    [ 2, 3, 4 ].each { get setup_path(step: it); assert_response :success }
  end

  test "提出書の宛先は確認済みの所轄庁から" do
    d = FilingDestination.create!(kind: "authority", name: "テスト市", addressee: "テスト市長　山田　太郎")
    FilingDestination::Confirmation.confirm!(d, by: users(:one))
    assert_equal "テスト市長　山田　太郎", FilingDestination.letter_addressee
  end
end
