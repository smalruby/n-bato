# 長いイベントの「いまの状態」が、詳細のイベントから作り直した状態と一致するかを確かめる(docs/adr/0005)。
# bin/rails model:verify で流す(CI と手元のデータ)。長いイベントを移したら、ここに照合を足す。
module ModelVerification
  module_function

  # 食い違いの一覧(文字列)。空なら一致。
  def mismatches
    voucher_mismatches + member_application_mismatches + registration_filing_mismatches + registration_mismatches + person_history_mismatches +
      todo_mismatches + incoming_request_mismatches
  end

  # やること: 状態・待つもの・済みの日時とひとことが、最後の状態の変化と同じか(docs/adr/0034)
  def todo_mismatches
    Todo.includes(:status_changes).filter_map do |t|
      diff = t.state_mismatches
      "やること ##{t.id}: #{diff.join('・')} が状態の変化と違う(いまの状態 #{t.status} / イベントから #{t.derived_state['status']})" if diff.any?
    end
  end

  # 依頼: 状態と解決した日が「解決にした」と同じか
  def incoming_request_mismatches
    IncomingRequest.includes(:settlement).filter_map do |r|
      next if r.state_mismatches.empty?

      want = r.derived_state
      "依頼 ##{r.id}: いまの状態 #{r.status}・#{r.resolved_on.inspect} / イベントから #{want['status']}・#{want['resolved_on'].inspect}"
    end
  end

  def voucher_mismatches
    Voucher.includes(:journal_proposals).filter_map do |v|
      derived = v.derived_status
      "証憑 ##{v.id}: いまの状態 #{v.status} / イベントから #{derived}" unless v.status == derived
    end
  end

  # 入会申込: 状態と、認めたときの人・年度・入会日(docs/adr/0030)
  def member_application_mismatches
    MemberApplication.includes(:approval, :rejection).flat_map do |a|
      list = []
      list << "入会申込 ##{a.id}: いまの状態 #{a.status} / イベントから #{a.derived_status}" unless a.status == a.derived_status
      if (e = a.approval) && [ a.person_id, a.fiscal_year, a.joined_on ] != [ e.person_id, e.fiscal_year, e.joined_on ]
        list << "入会申込 ##{a.id}: 認めたときの人・年度・入会日がイベントと違う"
      end
      list
    end
  end

  # 登記の申請: 状態(docs/adr/0031)
  def registration_filing_mismatches
    RegistrationFiling.includes(:submission, :acceptance, :corrections, :completion, :withdrawal).filter_map do |f|
      "登記の申請 ##{f.id}: いまの状態 #{f.status} / イベントから #{f.derived_status}" unless f.status == f.derived_status
    end
  end

  # 登記の事由: 登記した日は、入れた申請の完了の日
  def registration_mismatches
    Registration.includes(registration_filing: :completion).filter_map do |r|
      expected = r.registration_filing&.completion&.completed_on
      "登記の事由 ##{r.id}: 登記した日 #{r.registered_on.inspect} / 申請の完了から #{expected.inspect}" unless r.registered_on == expected || (r.registered_on && expected.nil? && r.registration_filing.nil?)
    end
  end

  # 人の住所・氏名: 記録の始まりと出来事から作り直して、氏名の出来事の「変わる前の氏名」がつながっているか(docs/adr/0029)
  def person_history_mismatches
    Person.includes(:address_changes, :name_changes).flat_map do |p|
      name = p.name_at_start
      p.active_name_changes.filter_map do |c|
        mismatch = "人 ##{p.id}: 氏名の出来事 ##{c.id} の変わる前の氏名が、作り直した氏名と違う" unless c.former_name == name
        name = c.name
        mismatch
      end
    end
  end
end
