# 架空のデータだけの環境の種(issue #14)。bin/demo(bin/rails demo:reset)とブラウザのテスト(test/system)が使う。
#
# - 名前・住所・連絡先はすべて架空(見本・架空・例示・仮名の氏、架空市、000 で始まる番号、example.com のメール)。
# - 記録は、アプリの作る入口(SIWAKE の取り込み・承認・決議の反映・登記の申請などのイベント)で作る。SQL では入れない。
# - 日付はきょうから決める(いつ流しても、いまの年度・締めた年度・仮の年度がそろう)。
require_relative "todos"

module Demo
  EMAIL = "ai@example.com".freeze
  NAME = "AI(架空のデータの確かめ役)".freeze

  def self.seed!(password:, today: Date.current) = Seed.new(password:, today:).run!

  class Seed
    ACCOUNTS = {
      100 => "現      金", 106 => "普通  預金",
      500 => "正会員受取会費", 510 => "受取寄付金", 520 => "受取助成金", 530 => "教室参加費収益", 550 => "受取  利息",
      630 => "会場費(事業)", 658 => "消耗品  費(事業)", 660 => "諸謝金(事業)",
      730 => "通信運搬費", 740 => "支払手数料", 750 => "租税  公課"
    }.freeze
    DEPARTMENTS = { 111 => [ "①事業", "①子ども向けの工作教室の運営事業" ], 112 => [ "②事業", "②見本の教材を作って配る事業" ],
                    900 => [ "管理部門", "管理部門" ] }.freeze
    PEOPLE = [
      { key: :chair, name: "見本　一郎", kana: "みほん　いちろう", email: "ichiro@example.com" },
      { key: :vice, name: "見本　二郎", kana: "みほん　じろう", email: "jiro@example.com" },
      { key: :director, name: "架空　花子", kana: "かくう　はなこ", email: "hanako@example.com" },
      { key: :auditor, name: "例示　春子", kana: "れいじ　はるこ", email: "haruko@example.com" },
      { key: :member1, name: "仮名　夏子", kana: "かめい　なつこ", email: "natsuko@example.com" },
      { key: :member2, name: "仮名　秋彦", kana: "かめい　あきひこ", email: "akihiko@example.com" }
    ].freeze

    attr_reader :user, :year, :today

    def initialize(password:, today:)
      @password = password
      @today = today
      @year = FiscalYear.for(today).year
      # 総会(役員の改選と事業報告の承認)は 6 月。今年の 6 月がまだなら去年の 6 月
      @meeting_year = Date.new(today.year, 6, 20) < today ? today.year : today.year - 1
    end

    def run!
      ActiveRecord::Base.transaction do
        create_user!
        section("法人と提出先") { organization!; filing_destinations!; articles! }
        section("会計") { accounting! }
        section("証憑と AI の提案") { vouchers! }
        section("会員と役員") { people! }
        # 総会の議決権は年度の正会員なので、入会を認めた人も決議の前に入れておく
        section("入会申込") { member_applications! }
        section("事業報告書") { annual_reports! }
        section("決議") { resolutions! }
        section("登記") { registrations! }
        section("手続き") { procedures! }
        section("やることと依頼") { Demo::Todos.build!(year:, today:) }
      end
      self
    end

    private

    def section(label, &)
      Audit.operation(user:, scope: "demo_seed", label: "架空のデータを入れた: #{label}", &)
    end

    def create_user!
      @user = User.create!(email_address: EMAIL, name: NAME, password: @password, roles: %w[clerk auditor], role: "clerk",
                           working_year: year)
    end

    def first_year = year - 3

    def organization!
      @org = Organization.create!(
        name: "NPO法人見本こども会", name_en: "Mihon Kodomo-kai", address: "架空市見本町1-2-3",
        representative_title: "理事長", representative_name: "見本　一郎", phone: "000-0000-0000",
        established_on: Date.new(first_year, 4, 10), first_fiscal_year: first_year, competent_authority: "架空市",
        settings: { "written_resolution_articles" => { "general_meeting" => "定款第２０条", "board" => "定款第２５条" } }
      )
      FiscalPeriod.ensure!
    end

    def filing_destinations!
      rows = [
        { kind: "authority", name: "架空市", addressee: "架空市長 様", office: "架空市役所 市民協働課(架空)",
          address: "架空市見本町2-3-4", phone: "000-0000-1000", email: "npo-office@example.com", hours: "平日 9:00〜17:00",
          source: "架空のデータ(実在しない窓口)", confirm: true },
        { kind: "registry", name: "架空地方法務局", addressee: "架空地方法務局　御中", office: "法人登記部門(架空)",
          address: "架空市見本町5-6-7", phone: "000-0000-2000", source: "架空のデータ(実在しない窓口)", confirm: true },
        { kind: "prefectural_tax", name: "架空県税事務所", office: "法人住民税の担当(架空)", address: "架空市見本町8-9-10",
          phone: "000-0000-3000", source: "架空のデータ(実在しない窓口)", confirm: false }
      ]
      rows.each_with_index do |row, i|
        d = FilingDestination.create!(row.except(:confirm).merge(origin: "human", position: i))
        FilingDestination::Confirmation.confirm!(d, by: user) if row[:confirm]
      end
    end

    # 定款の版と事業の主な活動は、リポジトリの例(config/articles.example.yml、架空)をそのまま使う
    def articles!
      path = Rails.root.join("config/articles.example.yml")
      conf = YAML.load_file(path, permitted_classes: [ Date ])
      Array(conf["versions"]).each do |h|
        ArticleVersion.create!(h.except("body_file").merge("body" => path.dirname.join(h.fetch("body_file")).read))
      end
      { 111 => "子ども向けの工作教室を月に 2 回開く(架空)", 112 => "見本の教材を作り、地域の学校に配る(架空)" }.each do |code, text|
        ProgramProfile.for(code).update!(activities: text)
      end
    end

    # 締めた年度・締める前の年度は、会計王から書き出した SIWAKE を取り込む(会計王が正の年度)。
    # いまの年度は、このアプリで手で入れた仕訳(直せる)。
    def accounting!
      (first_year..year - 1).each do |y|
        bytes = Kaikeiou::SiwakeFile.new(rows: siwake_rows(y)).to_bytes
        Kaikeiou::SiwakeImporter.new(bytes, filename: "demo_#{y}.txt").import
      end
      FiscalPeriod.ensure!
      Department.where(code: DEPARTMENTS.keys).find_each { it.update!(full_name: DEPARTMENTS.fetch(it.code).last) }
      OpeningBalance.create!(fiscal_year: first_year, account: account(first_year, 100), amount: 30_000)
      OpeningBalance.create!(fiscal_year: first_year, account: account(first_year, 106), amount: 150_000)
      FiscalPeriod.for(first_year).close!(by: user, on: Date.new(first_year + 1, 5, 20))
      FiscalPeriod.for(first_year + 1).close!(by: user, on: Date.new(first_year + 2, 5, 20))

      manual_entries.each do |date, debit, credit, amount, summary, dept|
        JournalEntry.create!(entry_date: date, amount:, debit_account: account(year, debit), credit_account: account(year, credit),
                             debit_department: dept && department(year, dept), summary:)
      end

      last = year - 1
      closing = Ledger::Book.new.statement(last).closing_balances.to_h { |a, amount| [ a.code, amount ] }
      BalanceCheck.create!(account: account(last, 106), checked_on: FiscalYear.new(last).ends_on, actual_amount: closing.fetch(106, 0),
                           note: "通帳の年度末の残高(架空)")
    end

    def account(y, code) = Account.find_by!(fiscal_year: y, code:)
    def department(y, code) = Department.find_by!(fiscal_year: y, code:)

    # 1 年分の仕訳(架空)。年度ごとに少しずつ金額を変える。
    def siwake_rows(y)
      k = y - first_year
      list = [
        [ 4, 10, 100, 0, 500, 900, 3_000 * (5 + k), "正会員受取会費", "#{y}年度の会費" ],
        [ 4, 28, 630, 111, 100, 0, 2_000, "公民館の会場費", "工作教室(架空)" ],
        [ 5, 12, 658, 111, 100, 0, 1_650 + (k * 110), "工作の材料", "見本文具店(架空)" ],
        [ 6, 1, 106, 0, 100, 0, 10_000, "現金を預金に預入れ", "" ],
        [ 7, 15, 106, 0, 520, 112, 50_000, "受取助成金", "架空財団の助成(架空)" ],
        [ 8, 3, 660, 112, 106, 0, 20_000, "教材作りの謝金", "教材作り(架空)" ],
        [ 9, 20, 100, 0, 530, 111, 4_500 + (k * 500), "教室参加費", "9 月の教室" ],
        [ 10, 5, 658, 112, 106, 0, 8_800, "教材の印刷", "見本印刷(架空)" ],
        [ 11, 11, 100, 0, 510, 0, 5_000, "受取寄付金", "" ],
        [ 12, 1, 730, 900, 100, 0, 840, "切手", "" ],
        [ 1, 20, 740, 900, 106, 0, 440, "振込手数料", "" ],
        [ 2, 20, 106, 0, 550, 0, 2, "利息", "" ],
        [ 3, 25, 750, 900, 106, 0, 1_000, "法人住民税の均等割(架空)", "" ]
      ]
      list.each_with_index.map do |(m, d, dc, dd, cc, cd, amount, summary, sub), i|
        date = Date.new(m >= 4 ? y : y + 1, m, d)
        side = ->(code, dept) { { account_code: code, account_name: ACCOUNTS.fetch(code), department_code: dept, department_name: dept.zero? ? "" : DEPARTMENTS.fetch(dept).first } }
        row = { slip_number: i + 1, line_number: 1, entry_date: date, summary:, sub_summary: sub, memo: "", tag1: 0, tag2: 0 }
        { debit: side.(dc, dd), credit: side.(cc, cd) }.each do |prefix, attrs|
          attrs.merge(sub_code: 0, sub_name: "", tax_category_code: 0, business_category_code: 0, tax_treatment_code: 3, tax_rate: 10,
                      amount:, tax_amount: 0).each { |a, v| row[:"#{prefix}_#{a}"] = v }
        end
        Kaikeiou::SiwakeFile::Row.new(**row)
      end
    end

    def manual_entries
      start = FiscalYear.new(year).starts_on
      [
        [ start + 9, 100, 500, 18_000, "正会員受取会費", nil ],
        [ start + 30, 630, 100, 2_000, "公民館の会場費", 111 ],
        [ start + 45, 658, 100, 1_980, "工作の材料", 111 ],
        [ start + 70, 106, 100, 10_000, "現金を預金に預入れ", nil ],
        [ start + 100, 100, 530, 6_000, "教室参加費", 111 ]
      ].map { |offset_date, *rest| [ [ offset_date, today ].min, *rest ] }
    end

    def vouchers!
      Voucher.create!(kind: "memo", description: "見本文具店(架空)で模造紙を 5 枚買った。1,100 円、現金。", amount: 1_100, issued_on: today - 2)

      proposed = Voucher.create!(kind: "receipt", description: "架空郵便局で切手を買った。840 円、現金。", amount: 840, issued_on: today - 5)
      JournalProposal.propose!(voucher: proposed, model: "claude-opus-5-5", entry_date: today - 5, amount: 840,
                               debit_account: account(year, 730), debit_department: department(year, 900), credit_account: account(year, 100),
                               summary: "切手", rationale: "郵便局の領収書で、品目が切手のため通信運搬費(架空のデータ)", confidence: "high")
      proposed.advance_status!

      booked = Voucher.create!(kind: "receipt", description: "見本印刷(架空)でちらしを刷った。3,300 円、振込。", amount: 3_300, issued_on: today - 20)
      proposal = JournalProposal.propose!(voucher: booked, model: "claude-opus-5-5", entry_date: today - 20, amount: 3_300,
                                          debit_account: account(year, 658), debit_department: department(year, 112),
                                          credit_account: account(year, 106), summary: "ちらしの印刷",
                                          rationale: "印刷の領収書。教材を配る事業のちらし(架空のデータ)", confidence: "medium")
      JournalProposal::Approval.approve!(proposal, by: user)
    end

    def people!
      @people = PEOPLE.to_h do |h|
        n = PEOPLE.index(h) + 1
        person = Person.create!(name: h[:name], name_kana: h[:kana], address: "架空市見本町#{n}-#{n}-#{n}", email: h[:email],
                                phone: "000-0000-00#{format('%02d', n)}")
        [ h[:key], person ]
      end
      (first_year..year).each do |y|
        @people.each_value { Membership.create!(person: it, fiscal_year: y, kind: "regular", joined_on: FiscalYear.new(y).starts_on + 9) }
      end
      Membership.create!(person: @people[:member2], fiscal_year: year, kind: "supporting")

      # いまの役員の、1 つ前の任期(2 年)。総会で改選する
      starts = Date.new(@meeting_year - 2, 6, 25)
      ends = Date.new(@meeting_year, 6, 24)
      { chair: "chair", vice: "vice_chair", director: "director", auditor: "auditor" }.each do |key, role|
        OfficerTerm.create!(person: @people.fetch(key), role:, starts_on: starts, ends_on: ends, appointed_by: "総会(架空)")
      end
    end

    def annual_reports!
      (first_year..year - 1).each do |y|
        report = AnnualReport.draft_for(y)
        report.achievements = "子ども向けの工作教室を開き、見本の教材を配った(架空のデータ)。"
        report.program_activities.each { it.assign_attributes(content: "#{it.department.long_name}(架空)", schedule: "毎月", beneficiaries: "地域の子ども 20 人(架空)") }
        report.save!
      end
      AnnualReport.find_by!(fiscal_year: first_year).update!(approved_on: Date.new(first_year + 1, 6, 20), submitted_on: Date.new(first_year + 1, 6, 28))
      AnnualReport.find_by!(fiscal_year: first_year + 1).update!(approved_on: Date.new(first_year + 2, 6, 20), submitted_on: Date.new(first_year + 2, 6, 28))
    end

    # 総会(書面決議): 役員の改選と事業報告の承認。理事会(書面決議): 理事長・副理事長の互選。
    def resolutions!
      proposed = Date.new(@meeting_year, 6, 1)
      gm = Resolution.create!(
        body: "general_meeting", voting_method: "written", title: "通常総会(書面決議)", proposed_on: proposed, proposer: @people[:chair],
        items_attributes: [
          { position: 0, kind: "officer_election", title: "第1号議案 役員選任の件",
            appointments_text: "見本　一郎 理事\n見本　二郎 理事\n架空　花子 理事\n例示　春子 監事" },
          { position: 1, kind: "annual_report_approval", title: "第2号議案 #{@meeting_year - 1}年度事業報告承認の件", fiscal_year: @meeting_year - 1 }
        ]
      )
      gm.voters.each_with_index { |p, i| gm.consents.create!(person: p, consented_on: proposed + 5 + i, via: i.even? ? "email" : "paper") }
      gm.items.each(&:apply!)

      established = gm.reload.established_on
      board = Resolution.create!(
        body: "board", voting_method: "written", title: "理事会(書面決議・互選)", proposed_on: established + 1, proposer: @people[:chair],
        items_attributes: [ { position: 0, kind: "officer_mutual_election", title: "理事長・副理事長の互選",
                              appointments_text: "見本　一郎 理事長\n見本　二郎 副理事長" } ]
      )
      board.voters.each { board.consents.create!(person: it, consented_on: established + 2, via: "email") }
      board.items.each(&:apply!)

      # 成立していない決議(同意を集めている途中)
      draft = Resolution.create!(body: "board", voting_method: "written", title: "理事会(書面決議・会場の変更)", proposed_on: [ today - 3, established + 3 ].max,
                                 proposer: @people[:chair], items_attributes: [ { position: 0, kind: "general", title: "教室の会場を変える件", content: "架空の公民館へ移す" } ])
      draft.consents.create!(person: @people[:chair], consented_on: draft.proposed_on, via: "email")
    end

    # 前の任期の就任の登記は済み、改選のあとの重任の登記は申請中、理事の住所の変更はまだ申請していない
    def registrations!
      old = Registration.where(registration_filing_id: nil).where(cause_on: ...Date.new(@meeting_year, 1, 1)).to_a
      if old.any?
        filing = RegistrationFiling.start!(old, note: "前の任期の就任(架空)")
        RegistrationFiling::Submission.submit!(filing, submitted_on: old.first.cause_on + 7, application_number: "00000000000001", by: user)
        RegistrationFiling::Acceptance.accept!(filing, accepted_on: old.first.cause_on + 8, receipt_number: "第0001号", by: user)
        RegistrationFiling::Completion.complete!(filing, completed_on: old.first.cause_on + 12, by: user)
      end
      recent = Registration.pending.where(registration_filing_id: nil).to_a
      if recent.any?
        filing = RegistrationFiling.start!(recent, note: "改選のあとの重任(架空)")
        RegistrationFiling::Submission.submit!(filing, submitted_on: [ recent.first.cause_on + 7, today ].min, application_number: "00000000000002", by: user)
      end
      Person::AddressChange.record!(@people[:vice], address: "架空市見本町9-9-9", moved_on: today - 4, by: user, note: "架空の転居")
    end

    def procedures!
      done = ProcedureRun.create!(kind: "annual_report", period: first_year + 1)
      on = Date.new(first_year + 2, 6, 28)
      done.steps.each do |step|
        next if step.definition.only_when
        # 年度はもう締めてある(会計の種)ので、締める手順は済みの記録だけ
        step.definition.effect == "close_year" ? step.update!(status: "done", completed_on: on) : step.complete!(on:)
      end

      run = ProcedureRun.create!(kind: "annual_report", period: year - 1)
      run.steps.first(2).each { it.complete!(on: Date.new(year, 5, 10)) }
      run.step(run.steps[2].key).tap { it.note = "監事に送った(架空)" }.save!

      return unless @meeting_year.even? # 役員の改選は偶数の年

      election = ProcedureRun.create!(kind: "officer_election", period: @meeting_year)
      established = Resolution.find_by!(body: "general_meeting").established_on
      election.steps.first(3).each { it.complete!(on: established) }
    end

    def member_applications!
      MemberApplication.create!(applied_on: today - 1, name: "仮名　冬美", name_kana: "かめい　ふゆみ", age_group: "40代",
                                postal_code: "000-0000", address: "架空市見本町7-7-7", email: "fuyumi@example.com", phone: "000-0000-0077",
                                source: "google_form", source_key: "demo-1")
      approved = MemberApplication.create!(applied_on: today - 30, name: "例示　秋子", name_kana: "れいじ　あきこ", postal_code: "000-0000",
                                           address: "架空市見本町8-8-8", email: "akiko@example.com", source: "google_form", source_key: "demo-2")
      MemberApplication::Approval.approve!(approved, fiscal_year: year, joined_on: today - 25, by: user)
      rejected = MemberApplication.create!(applied_on: today - 40, name: "見本　三郎", name_kana: "みほん　さぶろう",
                                           email: "saburo@example.com", source: "google_form", source_key: "demo-3")
      MemberApplication::Rejection.reject!(rejected, reason: "同じ人の申込が 2 回届いたため(架空)", by: user)
    end
  end
end
