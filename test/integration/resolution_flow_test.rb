require "test_helper"

class ResolutionFlowTest < ActionDispatch::IntegrationTest
  setup do
    import_sample
    Organization.create!(name: "NPO法人テスト", representative_title: "理事長", representative_name: "役員A", first_fiscal_year: 2024,
                         settings: { "written_resolution_articles" => { "general_meeting" => "定款第２９条第３項" } })
    @people = %w[役員A 役員B 役員C 監事D 会員E].map { Person.create!(name: it) }
    @people.each { Membership.create!(person: it, fiscal_year: 2026, kind: "regular") }
    start = Date.new(2022, 7, 1)
    finish = Date.new(2024, 6, 30)
    OfficerTerm.create!(person: @people[0], role: "chair", starts_on: start, ends_on: finish)
    OfficerTerm.create!(person: @people[1], role: "vice_chair", starts_on: start, ends_on: finish)
    OfficerTerm.create!(person: @people[2], role: "director", starts_on: start, ends_on: finish)
    OfficerTerm.create!(person: @people[3], role: "auditor", starts_on: start, ends_on: finish)
    AnnualReport.draft_for(2025).save!
    sign_in
  end

  test "総会の書面決議で役員を再任し、事業報告を承認し、理事会で互選する" do
    travel_to Date.new(2026, 11, 25) do
      post resolutions_path, params: { resolution: {
        body: "general_meeting", voting_method: "written", title: "通常総会（書面決議）", proposed_on: "2026-11-25", proposer_id: @people[0].id,
        items_attributes: {
          "0" => { position: 0, kind: "officer_election", title: "第1号議案 役員選任の件", appointments_text: "役員A 理事\n役員B 理事\n役員C 理事\n監事D 監事" },
          "1" => { position: 1, kind: "annual_report_approval", title: "第2号議案 2025年度事業報告承認の件", fiscal_year: "2025" }
        }
      } }
      gm = Resolution.last
      assert_redirected_to resolution_path(gm)
      assert_equal 5, gm.voters.size
      assert_not gm.established?

      @people.each_with_index do |p, i|
        post resolution_consents_path(gm), params: { consent: { person_id: p.id, consented_on: "2026-12-0#{i + 1}", via: "email" } }
      end
      assert_equal Date.new(2026, 12, 5), gm.reload.established_on

      get document_resolution_path(gm, "minutes")
      assert_match "令和８年１２月５日", response.body
      assert_match "定款第２９条第３項", response.body

      gm.items.each { post apply_item_resolution_path(gm, item_id: it.id) }
      assert_equal Date.new(2026, 12, 5), AnnualReport.find_by!(fiscal_year: 2025).approved_on
      new_terms = OfficerTerm.where(starts_on: Date.new(2026, 12, 5))
      assert_equal 4, new_terms.count
      assert_equal Date.new(2028, 12, 4), new_terms.first.ends_on
      assert_equal 0, Registration.where(cause_on: Date.new(2026, 12, 5)).count # 理事として選任しただけでは代表権なし

      # 旧任期は新しい選任の前日まで
      old_chair = OfficerTerm.find_by!(person: @people[0], role: "chair")
      assert_equal Date.new(2026, 12, 4), old_chair.last_day

      post resolutions_path, params: { resolution: {
        body: "board", voting_method: "written", title: "理事会（互選）", proposed_on: "2026-12-06", proposer_id: @people[0].id,
        items_attributes: { "0" => { position: 0, kind: "officer_mutual_election", title: "理事長・副理事長の互選", appointments_text: "役員A 理事長\n役員B 副理事長" } }
      } }
      board = Resolution.last
      assert_equal 3, board.voters.size
      @people[0..2].each { post resolution_consents_path(board), params: { consent: { person_id: it.id, consented_on: "2026-12-07", via: "paper" } } }
      post apply_item_resolution_path(board, item_id: board.items.first.id)
      assert_equal "chair", OfficerTerm.find_by!(person: @people[0], starts_on: Date.new(2026, 12, 5)).role
      reg = Registration.find_by!(cause_on: Date.new(2026, 12, 7), note: "役員A（理事長）の就任・重任")
      assert_equal Date.new(2026, 12, 21), reg.due_on
    end
    assert_pdf document_resolution_path(Resolution.find_by!(body: "general_meeting"), "minutes", format: :pdf)
  end

  test "読めない氏名はエラー" do
    post resolutions_path, params: { resolution: {
      body: "general_meeting", voting_method: "written", title: "x", proposed_on: "2026-11-25", proposer_id: @people[0].id,
      items_attributes: { "0" => { kind: "officer_election", title: "選任", appointments_text: "知らない人 理事" } }
    } }
    assert_response :unprocessable_entity
    assert_match "知らない人", response.body
  end
end
