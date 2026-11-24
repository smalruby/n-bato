require "test_helper"

# 決議の画面(一覧・開く・新規・編集・削除)と、同意の記録の取り消し、成立前の反映
class ResolutionScreensTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    ensure_organization
    FiscalPeriod.ensure!
    @chair = Person.create!(name: "役員A")
    @member = Person.create!(name: "会員B")
    OfficerTerm.create!(person: @chair, role: "chair", starts_on: Date.current - 30, ends_on: Date.current + 300)
    [@chair, @member].each { Membership.create!(person: it, fiscal_year: FiscalYear.current.year, kind: "regular") }
    @resolution = Resolution.create!(body: "general_meeting", voting_method: "written", title: "書面決議", proposed_on: Date.current, proposer: @chair,
      items_attributes: [{position: 0, kind: "annual_report_approval", title: "第1号議案", fiscal_year: FiscalYear.current.year - 1}])
  end

  test "一覧・開く・新規の画面(提案者は理事長)" do
    get resolutions_path
    assert_response :success
    assert_match "書面決議", response.body

    get resolution_path(@resolution)
    assert_response :success

    get new_resolution_path(body: "board")
    assert_response :success
    assert_select "select[name='resolution[proposer_id]'] option[selected][value='#{@chair.id}']"
  end

  test "編集する・保存できなければ戻す・削除する" do
    get edit_resolution_path(@resolution)
    assert_response :success

    patch resolution_path(@resolution), params: {resolution: {title: "書面決議(改)"}}
    assert_redirected_to resolution_path(@resolution)
    assert_equal "書面決議(改)", @resolution.reload.title

    patch resolution_path(@resolution), params: {resolution: {title: ""}}
    assert_response :unprocessable_entity

    delete resolution_path(@resolution)
    assert_redirected_to resolutions_path
    assert_not Resolution.exists?(@resolution.id)
  end

  test "同意の記録: 足せないときは知らせ、取り消せる" do
    post resolution_consents_path(@resolution), params: {consent: {person_id: @member.id, consented_on: "", via: "email"}}
    assert flash[:alert].present?

    post resolution_consents_path(@resolution), params: {consent: {person_id: @member.id, consented_on: Date.current.iso8601, via: "email"}}
    consent = @resolution.consents.sole
    post resolution_consent_cancellation_path(@resolution, consent)
    assert_equal "同意の記録を取り消しました", flash[:notice]
    assert_empty @resolution.consents.reload
  end

  test "成立していない決議は記録に反映しない" do
    post resolution_item_application_path(@resolution, @resolution.items.first)
    assert_equal "決議が成立していません", flash[:alert]
  end
end
