require "test_helper"

# ブラウザの「戻る」を使わなくてよい画面(見直し第21回、docs/adr/0033)
class NavigationTest < ActionDispatch::IntegrationTest
  setup { ensure_organization; sign_in }

  test "詳しい画面の題の上にパンくずがあり、一覧へ最後の絞り込みのまま戻れる" do
    person = Person.create!(name: "行き　来")

    get people_path(q: "行き")
    get person_path(person)
    assert_select "nav.nb-crumb a[href=?]", people_path(q: "行き"), text: "会員・役員"
    assert_select "nav.nb-crumb [aria-current=page]", text: "行き　来"

    get people_path # 絞り込みなしで開いたら、覚えていた絞り込みは消す
    get edit_person_path(person)
    assert_select "nav.nb-crumb a[href=?]", people_path
    assert_select "nav.nb-crumb a[href=?]", person_path(person), text: "行き　来"
    assert_select "nav.nb-crumb [aria-current=page]", text: "編集"
  end

  test "作る画面にもパンくずがある" do
    { new_person_path => "会員・役員", new_voucher_path => "証憑・AI 仕訳", new_journal_entry_path => "仕訳",
      new_resolution_path => "決議", new_siwake_import_path => "会計(年度)", member_applications_path => "会員・役員" }.each do |path, up|
      get path
      assert_response :success
      assert_select "nav.nb-crumb a", text: up
    end
  end

  test "PDF と外のサイトへのリンクは別のタブで開き、↗ を付ける" do
    get filing_destinations_path
    assert_select "a[href=?][target=_blank][rel=noopener]", filing_samples_path(format: :pdf), text: /↗/
    get registrations_path
    assert_select "a[target=_blank][rel=noopener]", text: /登記・供託オンライン申請システムを開く ↗/
  end
end
