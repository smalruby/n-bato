require "application_system_test_case"

# 使えない操作の理由(デザインシステム DisabledAction、見直し第22回)。架空のデータの決議(同意を記録してあるので消せない)で確かめる。
class DisabledActionTest < ApplicationSystemTestCase
  setup do
    sign_in_as_ai
    @resolution = Resolution.find_by!(body: "general_meeting")
    visit resolution_path(@resolution)
    @wrap = find(".nb-disabled-action", text: "削除")
    @button = @wrap.find("button[aria-disabled=true]", text: "削除")
    @info = @wrap.find(".nb-info-tip")
  end

  def tip = find("##{@button['aria-describedby']}", visible: :all)

  test "カーソルを当てると説明が出て、離すと消える。灰色のボタンを押しても消えない" do
    assert_not tip.visible?
    @button.hover
    assert_selector ".nb-tip", text: "この決議は消せません", visible: true
    assert_text "同意の記録を見る"
    find("h1").hover
    assert_no_selector ".nb-tip", visible: true

    execute_script("arguments[0].click()", @button) # 灰色のボタンは Playwright からは押せない(押せないと分かる)ので、ページの中から押す
    assert_selector ".nb-tip", visible: true # 押すと説明が出る
    assert_current_path resolution_path(@resolution)
    assert Resolution.exists?(@resolution.id)
  end

  test "(i) を押すと出したままになり、もう一度押す・外を押すと閉じる" do
    @info.click
    assert_selector ".nb-tip", text: "書面決議の記録として残すため", visible: true
    assert_equal "true", @info["aria-expanded"]
    find("h1").hover
    assert_selector ".nb-tip", visible: true # 押して出したものは、カーソルを離しても残す

    @info.click
    assert_no_selector ".nb-tip", visible: true
    assert_equal "false", @info["aria-expanded"]

    @info.click
    assert_selector ".nb-tip", visible: true
    find("h1").click
    assert_no_selector ".nb-tip", visible: true
  end

  test "キーボードで (i) に移ると出て、Esc で閉じる。リンクで同意の記録へ移れる" do
    execute_script("document.querySelector('.nb-disabled-action .nb-info-tip').focus()")
    assert_selector ".nb-tip", visible: true
    @info.send_keys(:escape)
    assert_no_selector ".nb-tip", visible: true
    assert_equal "使えない理由", evaluate_script("document.activeElement.getAttribute('aria-label')")

    @info.send_keys(:tab) # 閉じたまま次へ。もう一度 (i) に戻ると出る
    @info.click
    within(".nb-tip") { click_on "同意の記録を見る" }
    page.document.synchronize { evaluate_script("location.hash") == "#consents" or raise Capybara::ExpectationNotMet, "同意の記録へ移っていない" }
  end

  test "スマホの幅(390px)でも、説明は画面からはみ出さない" do
    page.driver.with_playwright_page { it.set_viewport_size(width: 390, height: 844) }
    visit resolution_path(@resolution)
    find(".nb-disabled-action", text: "削除").find(".nb-info-tip").click
    assert_selector ".nb-tip", visible: true
    left, right = evaluate_script("(() => { const r = document.querySelector('.nb-tip:not([hidden])').getBoundingClientRect(); return [r.left, r.right] })()")
    assert_operator left, :>=, 0
    assert_operator right, :<=, 390
    assert_equal 0, horizontal_overflow
  end
end
