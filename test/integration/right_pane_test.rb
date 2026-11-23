require "test_helper"

# 右ペイン: この画面の使い方(HelpPanel)と AI に聞く(AskAI)、監査の役割
class RightPaneTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    [ 2024, 2025 ].each { FiscalPeriod.find_or_create_by!(year: it) }
  end

  test "説明は役割と状態に合わせて出し、畳んだことを画面ごとに覚える" do
    get journal_entries_path(year: 2025)
    assert_select ".nb-help .nb-help-role", text: "事務"
    assert_select ".nb-help-now li", text: /仮/
    assert_select ".nb-help-ops dt", minimum: 3

    post help_pref_path, params: { screen: "journal_entries", collapsed: "1" }
    get journal_entries_path
    assert_select ".nb-help-body[hidden]"
    get accounts_path
    assert_select ".nb-help-body:not([hidden])"
  end

  test "監査の役割には、出ているもの・出せるものを説明し、記録は変えさせない" do
    users(:one).update!(role: "auditor")
    get journal_entries_path(year: 2024)
    assert_select ".nb-help .nb-help-role", text: "監査"
    assert_select ".nb-help h3", text: "ほかに出せるもの"

    post people_path, params: { person: { name: "新しい人" } }
    assert_redirected_to root_path
    assert_nil Person.find_by(name: "新しい人")
  end

  test "AI の鍵が無ければ、そう答える" do
    post assistant_path, params: { q: "仕訳して", screen: "journal_entries" }
    assert_match "AI の鍵", response.parsed_body["answer"] unless Bookkeeper::Client.configured?
  end

  test "個人情報を含む頼みごと(会員の記録を直す)は、AI の案にしない" do
    action, problem = Assistant::Action.prepare({ "kind" => "update_person" }, year: 2025)
    assert_nil action
    assert_nil problem
    assert_not_includes Assistant::Responder::SCHEMA.dig(:properties, :action, :properties, :kind, :enum), "update_person"
  end

  test "役割は上部バーで切り替え、監査のときは帯を出す。切り替えられない役割には変えない" do
    get journal_entries_path
    assert_select ".nb-role-switch summary", text: /事務として使う/
    assert_select ".nb-role-band", count: 0

    patch role_path, params: { role: "auditor" }
    assert_equal "auditor", users(:one).reload.role
    get journal_entries_path
    assert_select ".nb-role-band", text: /監査として見ています/
    assert_select ".nb-role-band button", text: "事務に切り替える"

    patch role_path, params: { role: "clerk" }   # 監査で使っていても切り替えられる
    assert_equal "clerk", users(:one).reload.role

    sign_in users(:two)
    patch role_path, params: { role: "auditor" }
    assert_equal "clerk", users(:two).reload.role
    get journal_entries_path
    assert_select ".nb-role-chip", text: /事務として使う/
    assert_select ".nb-role-switch", count: 0
  end
end
