require "test_helper"
require "rake"

# 手続き・決議・提出の画面から作る出来事(docs/adr/0038)。画面の見た目と動きは変えていない。データは架空。
class ProcedureResolutionEventsFlowTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    ensure_organization
    FiscalPeriod.ensure!
    @run = ProcedureRun.create!(kind: "annual_report", period: 2025)
  end

  test "手順を済みにする・二度押し・済みを取り消す(同じ状態のときは「元に戻せます」と言わない)" do
    post procedure_step_status_changes_path(@run, "close_books"), params: { status: "done", completed_on: "2026-04-10" }
    assert_match "を済みにしました(元に戻せます)", flash[:notice]
    step = @run.procedure_steps.find_by!(key: "close_books")
    assert_equal Date.new(2026, 4, 10), step.completed_on

    post procedure_step_status_changes_path(@run, "close_books"), params: { status: "done" }
    assert_no_match "元に戻せます", flash[:notice]
    assert_match "もう済みにしてあります", flash[:notice]
    assert_equal 1, step.status_changes.count

    post procedure_step_status_changes_path(@run, "close_books"), params: { status: "open" }
    assert_equal "済みを取り消しました", flash[:notice]
    post procedure_step_status_changes_path(@run, "close_books"), params: { status: "open" }
    assert_match "まだ済みにしていません", flash[:notice]

    post procedure_step_status_changes_path(@run, "close_books"), params: { status: "nope" }
    assert_equal "状態が分かりません", flash[:alert]
    post procedure_step_status_changes_path(@run, "close_books"), params: { status: "done", completed_on: "2026-99-99" }
    assert_equal "日付を入れてください", flash[:alert]

    get procedure_path(@run, step: "close_books")
    assert_select "form[action=?] input[name=status][value=done]", procedure_step_status_changes_path(@run, "close_books")
  end

  test "final の手順を済みにしたら、対象外・取り消しは画面の知らせで断る。optional でない手順は対象外にできない" do
    create_annual_report!(2025)
    post procedure_step_status_changes_path(@run, "submit"), params: { status: "done", completed_on: "2026-06-28" }
    post procedure_step_status_changes_path(@run, "submit"), params: { status: "skipped", reason: "間違えた" }
    assert_equal "この手順は済みにしたので、もう変えられません", flash[:alert]
    post procedure_step_status_changes_path(@run, "submit"), params: { status: "done", completed_on: "2026-07-15" }
    assert_match "もう済みにしてあります", flash[:notice]
    assert_equal Date.new(2026, 6, 28), AnnualReport.find_by!(fiscal_year: 2025).submitted_on
    assert_equal 1, ProcedureStep::StatusChange.count

    post procedure_step_status_changes_path(@run, "audit"), params: { status: "skipped" }
    assert_equal "この手順は対象外にできません", flash[:alert]
    assert_equal "open", @run.step("audit")[:status]
  end

  test "監査の役割では、手順の状態・同意の取消・議案の反映を作れない" do
    chair = Person.create!(name: "役員A")
    resolution = Resolution.create!(body: "board", voting_method: "meeting", title: "会議の決議", proposed_on: Date.current, held_on: Date.current, proposer: chair)
    item = resolution.items.create!(kind: "officer_election", title: "選任", payload: { "appointments" => [] })
    consent = Consent.record!(resolution, person: chair, consented_on: Date.current)
    users(:one).update!(role: "auditor")

    post procedure_step_status_changes_path(@run, "close_books"), params: { status: "done" }
    assert_equal "監査の役割では、記録を変えられません", flash[:alert]
    post resolution_consent_cancellation_path(resolution, consent)
    assert_equal "監査の役割では、記録を変えられません", flash[:alert]
    post resolution_item_application_path(resolution, item)
    assert_equal "監査の役割では、記録を変えられません", flash[:alert]
    assert_equal [ 0, 0, 0 ], [ ProcedureStep::StatusChange.count, Consent::Cancellation.count, ResolutionItem::Application.count ]
  end

  test "data:load: 事業報告の日付・過去の提出日は節目として記録する(架空のデータ)" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("data:load")
    Rake::Task["data:load"].reenable
    Dir.mktmpdir do |dir|
      path = File.join(dir, "records.yml")
      File.write(path, { "annual_reports" => [ { "fiscal_year" => 2024, "achievements" => "架空の成果", "approved_on" => Date.new(2025, 6, 20), "submitted_on" => Date.new(2025, 6, 28) } ],
                         "past_submissions" => [ { "fiscal_year" => 2023, "submitted_on" => Date.new(2024, 6, 27) } ] }.to_yaml)
      capture_io { Rake::Task["data:load"].invoke(path) }
    end
    report = AnnualReport.find_by!(fiscal_year: 2024)
    assert_equal [ "架空の成果", Date.new(2025, 6, 20), Date.new(2025, 6, 28) ], [ report.achievements, report.approved_on, report.submitted_on ]
    assert_equal %w[approved submitted], report.milestones.map(&:kind)
    assert_equal [ "submitted" ], AnnualReport.find_by!(fiscal_year: 2023).milestones.map(&:kind)
    assert_empty ModelVerification.mismatches
  end

  test "手続きを始めるを二度押ししても 1 つ" do
    2.times { post procedures_path, params: { kind: "officer_election", period: 2026 } }
    assert_equal 1, ProcedureRun.where(kind: "officer_election", period: 2026).count
    assert_redirected_to procedure_path(ProcedureRun.find_by!(kind: "officer_election"))
  end

  test "事業報告の画面で日付を直すと、節目を記録する(変わった欄だけ。消すこともできる)" do
    AnnualReport.draft_for(2024).save!
    patch annual_report_path(2024), params: { annual_report: { submitted_on: "2026-06-01", approved_on: "", bs_published_on: "", achievements: "成果" } }
    report = AnnualReport.find_by!(fiscal_year: 2024)
    assert_equal [ Date.new(2026, 6, 1), "成果" ], [ report.submitted_on, report.achievements ]
    assert_equal [ "submitted" ], report.milestones.map(&:kind)

    patch annual_report_path(2024), params: { annual_report: { submitted_on: "2026-06-01", achievements: "成果2" } }
    assert_equal 1, report.milestones.count
    patch annual_report_path(2024), params: { annual_report: { submitted_on: "" } }
    assert_nil report.reload.submitted_on
    assert_equal 2, report.milestones.count

    post annual_reports_path, params: { annual_report: { fiscal_year: 2025, approved_on: "2026-06-20" } }
    assert_equal Date.new(2026, 6, 20), AnnualReport.find_by!(fiscal_year: 2025).approved_on
    post annual_reports_path, params: { annual_report: { fiscal_year: 2025, approved_on: "2026-06-21" } }
    assert_response :unprocessable_entity
    assert_select "input[name='annual_report[approved_on]'][value='2026-06-21']"
    assert_empty ModelVerification.mismatches
  end

  test "事業報告の画面: 開いたときの日付を送り、変えていない欄は記録しない。開いている間に手続きが変えた日付は上書きしない" do
    report = create_annual_report!(2025)
    get edit_annual_report_path(2025)
    assert_select "input[type=hidden][name='opened_dates[submitted_on]'][value='']"
    # 画面を開いている間に、手続きで提出した日を記録した
    ProcedureStep::StatusChange.change!(@run.step("submit"), status: "done", on: Date.new(2026, 6, 28))

    # 日付の欄を変えずに保存すると、手続きが記録した日付は消さない
    patch annual_report_path(2025), params: { opened_dates: { submitted_on: "", approved_on: "", bs_published_on: "" },
                                              annual_report: { submitted_on: "", approved_on: "", bs_published_on: "", achievements: "成果" } }
    assert_equal "保存しました", flash[:notice]
    assert_equal [ Date.new(2026, 6, 28), "成果" ], [ report.reload.submitted_on, report.achievements ]
    assert_equal 1, report.milestones.count

    # 開いたあとに変わった欄を直そうとすると、断って新しい日付を欄に出す(何も保存しない)
    patch annual_report_path(2025), params: { opened_dates: { submitted_on: "", approved_on: "" },
                                              annual_report: { submitted_on: "2026-07-01", approved_on: "2026-06-20", achievements: "成果2" } }
    assert_response :unprocessable_entity
    assert_select ".nb-flash--alert", /所轄庁への提出日は、この画面を開いたあとに別の操作で 2026\/06\/28 に変わっています/
    assert_select "input[name='annual_report[submitted_on]'][value='2026-06-28']"
    assert_select "input[type=hidden][name='opened_dates[submitted_on]'][value='2026-06-28']"
    assert_select "input[name='annual_report[approved_on]'][value='2026-06-20']"
    assert_select "input[type=hidden][name='opened_dates[approved_on]'][value='']"
    assert_equal [ Date.new(2026, 6, 28), nil, "成果" ], [ report.reload.submitted_on, report.approved_on, report.achievements ]

    # 開き直して(新しい日付を見て)から直すのは、ふつうに記録する
    patch annual_report_path(2025), params: { opened_dates: { submitted_on: "2026-06-28" }, annual_report: { submitted_on: "2026-07-01" } }
    assert_equal Date.new(2026, 7, 1), report.reload.submitted_on
    assert_empty ModelVerification.mismatches
  end

  test "同意を取り消しても記録は残り、記録し直せる。同意のある決議は消せない。反映の二度押しは伝える" do
    chair = Person.create!(name: "役員A")
    OfficerTerm.create!(person: chair, role: "chair", starts_on: Date.current - 30, ends_on: Date.current + 300)
    Membership.create!(person: chair, fiscal_year: FiscalYear.current.year, kind: "regular")
    create_annual_report!(FiscalYear.current.year - 1)
    resolution = Resolution.create!(body: "general_meeting", voting_method: "written", title: "書面決議", proposed_on: Date.current, proposer: chair,
                                    items_attributes: [ { position: 0, kind: "annual_report_approval", title: "第1号議案", fiscal_year: FiscalYear.current.year - 1 } ])
    post resolution_consents_path(resolution), params: { consent: { person_id: chair.id, consented_on: Date.current.iso8601, via: "email" } }
    post resolution_consents_path(resolution), params: { consent: { person_id: chair.id, consented_on: Date.current.iso8601, via: "email" } }
    assert_match "もう記録してあります", flash[:alert]
    consent = resolution.consents.sole

    post resolution_consent_cancellation_path(resolution, consent)
    assert_equal "同意の記録を取り消しました", flash[:notice]
    post resolution_consent_cancellation_path(resolution, consent)
    assert_equal "もう取り消してあります", flash[:alert]
    assert Consent.exists?(consent.id)

    post resolution_consents_path(resolution), params: { consent: { person_id: chair.id, consented_on: Date.current.iso8601, via: "paper" } }
    assert resolution.reload.established?
    item = resolution.items.first
    post resolution_item_application_path(resolution, item)
    assert_equal "「第1号議案」を記録に反映しました", flash[:notice]
    post resolution_item_application_path(resolution, item)
    assert_equal "もう記録に反映してあります", flash[:alert]
    # 反映した議案のある決議の同意は、取り消せない(ボタンはそのまま。押すとわけを出す)
    post resolution_consent_cancellation_path(resolution, resolution.consents.sole)
    assert_equal "記録に反映した議案があるので、同意の記録は取り消せません", flash[:alert]
    assert resolution.reload.established?

    delete resolution_path(resolution)
    assert_redirected_to resolution_path(resolution)
    assert_match "消せません", flash[:alert]
    assert Resolution.exists?(resolution.id)
  end
end
