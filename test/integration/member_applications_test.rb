require "test_helper"
require "rake"

# 入会申込(デザインシステム「入会申込」、見直し第11回)
class MemberApplicationsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    [ 2025, 2026 ].each { FiscalPeriod.find_or_create_by!(year: it) }
    Organization.create!(name: "NPO法人テスト", address: "テスト市", representative_title: "理事長", representative_name: "役員A",
                         first_fiscal_year: 2023, competent_authority: "テスト市", phone: "000-0000-0000")
    @app = MemberApplication.create!(applied_on: Date.new(2026, 12, 1), name: "会員　花子", name_kana: "かいいん　はなこ",
                                     postal_code: "000-0000", address: "テスト市1-2-3", email: "h@example.jp", phone: "000-1111-2222")
  end

  test "届いた申込はやることに出て、認めると人と正会員の資格ができる" do
    get todos_path
    assert_match "入会申込が届いた: 会員　花子", response.body

    get member_application_path(@app)
    assert_response :success
    assert_match "入会を認める", response.body

    post approve_member_application_path(@app), params: { fiscal_year: 2026, joined_on: "2026-12-02" }
    @app.reload
    assert @app.approved?
    person = @app.person
    assert_equal "〒000-0000 テスト市1-2-3", person.address
    assert person.member_in?(2026)
    assert_equal Date.new(2026, 12, 2), person.memberships.first.joined_on

    get member_application_path(@app)
    assert_match "入会のお知らせメールの下書き", response.body
    assert_match "2026年12月2日付けで", response.body
    get todos_path
    assert_no_match "入会申込が届いた", response.body
  end

  test "同じ氏名の人がいれば、その人に資格を足す" do
    p = Person.create!(name: "会員　花子")
    post approve_member_application_path(@app), params: { fiscal_year: 2026, joined_on: "2026-12-02", person_id: p.id }
    assert_equal p, @app.reload.person
    assert_equal 1, Person.where(name: "会員　花子").count
  end

  test "認めないときは理由が要る" do
    post reject_member_application_path(@app), params: { reason: "" }
    assert @app.reload.received?
    post reject_member_application_path(@app), params: { reason: "連絡がとれない" }
    assert @app.reload.rejected?
  end

  test "フォームの回答を JSON から入れる(同じ回答は二度入れない)" do
    file = Rails.root.join("tmp/test_applications.json")
    File.write(file, [ { source_key: "r1", applied_on: "2026-12-03", name: "会員　次郎", address: "テスト市9" } ].to_json)
    Rails.application.load_tasks unless Rake::Task.task_defined?("member_applications:import")
    ENV["FILE"] = file.to_s
    2.times { Rake::Task["member_applications:import"].reenable; assert_output(/入会申込を/) { Rake::Task["member_applications:import"].invoke } }
    assert_equal 1, MemberApplication.where(source_key: "r1").count
  ensure
    ENV.delete("FILE")
    File.delete(file) if file && File.exist?(file)
  end
end
