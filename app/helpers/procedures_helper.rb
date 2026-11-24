module ProceduresHelper
  STEP_MARKS = {"done" => "✓", "waiting" => "…", "overdue" => "!", "skipped" => "－"}.freeze

  def step_mark(step, index) = STEP_MARKS[step.status] || (index + 1).to_s

  # 手順の一覧の下の行(状態の補足)
  def step_meta(step)
    case step.status
    when "done" then step.completed_on ? "済み #{step.completed_on.strftime("%Y/%m/%d")}" : "済み(記録から)"
    when "skipped" then step.note.presence&.truncate(16) || "対象外"
    when "overdue" then "期限 #{step.run.due_on.strftime("%Y/%m/%d")}"
    when "waiting" then "返事 #{step.wait_items.count { step.checked?(it) }}/#{step.wait_items.size}"
    when "current" then "#{step.checks.size}/#{step.all_items.size} 確認"
    else "未着手"
    end
  end

  def step_tag_class(step)
    {"done" => "nb-tag--done", "waiting" => "nb-tag--soon", "overdue" => "nb-tag--overdue"}.fetch(step.status, "nb-tag--plain")
  end

  # 期限までの日数(Deadline)
  def due_badge(run)
    days = run.days_left
    if run.finished?
      tag.span(class: "nb-due") { safe_join(["期限 #{run.due_on.strftime("%Y/%m/%d")}", tag.strong("済み")]) }
    elsif days.negative?
      tag.span(class: "nb-due nb-due--overdue") { safe_join(["期限 #{run.due_on.strftime("%Y/%m/%d")}", tag.strong("#{-days} 日超過")]) }
    else
      tag.span(class: ["nb-due", ("nb-due--soon" if days <= 30)]) { safe_join(["期限 #{run.due_on.strftime("%Y/%m/%d")}", tag.strong("あと #{days} 日")]) }
    end
  end

  def progress_bar(run)
    total = run.steps.size.to_f
    tag.span(class: "nb-progress") do
      safe_join([
        tag.span(class: "nb-progress-bar", "aria-hidden": "true") do
          safe_join([tag.span(style: "width:#{run.done_count / total * 100}%"),
            tag.span(class: "waiting", style: "width:#{run.waiting_count / total * 100}%")])
        end,
        "#{run.done_count} / #{run.steps.size} 済み"
      ])
    end
  end

  # 手順の定義の links を、この手続きの画面へのリンクにする。
  def procedure_link(name, run)
    year = run.period
    report = run.annual_report
    label, path = case name
    when "fiscal_year" then ["#{year}年度の会計", fiscal_year_path(year)]
    when "balance_checks" then ["残高の照合", balance_checks_path]
    when "statement_activity" then ["活動計算書", fiscal_year_statement_path(year, "activity")]
    when "statement_balance_sheet" then ["貸借対照表", fiscal_year_statement_path(year, "balance_sheet")]
    when "annual_report_edit" then report ? ["事業報告を書く", edit_annual_report_path(year)] : ["事業報告を作る", new_annual_report_path(year:)]
    when "document_business_report" then report && ["事業報告書(帳票)", document_annual_report_path(year, "business_report")]
    when "document_letter" then report && ["提出書(帳票)", document_annual_report_path(year, "letter")]
    when "pack" then report && ["書類一式(帳票)", pack_annual_report_path(year)]
    when "resolutions" then ["決議の一覧", resolutions_path]
    when "new_resolution" then ["決議を作る", new_resolution_path]
    when "people" then ["会員・役員", people_path]
    when "officer_terms" then ["役員の任期", people_path]
    when "registrations" then ["登記", registrations_path]
    when "articles" then ["定款と事業(主な活動)", articles_path]
    end
    link_to(label, path, class: "nb-btn") if label
  end
end
