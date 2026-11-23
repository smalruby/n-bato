module SlackNotice
  # 記録の知らせ: 操作の記録(AuditOperation)を前回の続きから見て、次のことを流す。
  # - 締めた年度の変更(理由のある操作): 誰が・いつ・何を・理由。会員・役員などの記録は値を出さない
  # - 年度を締めた・締めを解いた・次の年度を始めた
  # - 監事の監査の手順を済みにした、所轄庁への提出を記録した
  class Activity
    PERSONAL = %w[Person PersonYear Membership OfficerTerm Consent User Organization OrganizationYear IncomingRequestMessage MemberApplication].freeze
    CURSOR = "cursor:audit"

    def run!
      cursor = SlackPost.find_or_create_by!(key: CURSOR) { it.text = (AuditOperation.maximum(:id) || 0).to_s }
      last = cursor.text.to_i
      AuditOperation.where("id > ?", last).where(kind: %w[do final]).order(:id).includes(:audit_changes).each do |op|
        notify(op)
        last = op.id
      end
      cursor.update!(text: last.to_s)
    end

    private

    def notify(op)
      who = op.user&.name.presence || "だれか"
      at = op.created_at.in_time_zone("Asia/Tokyo").strftime("%-m/%-d %H:%M")
      changes = op.audit_changes.to_a
      changes.each { milestone(op, it, who, at) }
      return if op.reason.blank?

      years = changes.filter_map(&:fiscal_year).uniq.sort
      lines = changes.first(5).map { "・#{describe(it)}" }
      lines << "(ほか #{changes.size - 5} 件)" if changes.size > 5
      SlackNotice.post!("op-#{op.id}", ([ "*締めた年度の変更* #{years.map { "#{it}年度" }.join('・')} #{op.label}", *lines,
                                         "理由: #{op.reason}", "変えた人: #{who} #{at}", SlackNotice.link("/changes#{"?year=#{years.first}" if years.any?}", "変更の記録を開く") ]).join("\n"))
    end

    def describe(change)
      return "#{change.model_label}の記録(個人情報のため、値は出しません)" if PERSONAL.include?(change.auditable_type)
      return change.summary unless change.event == "update"

      (change.changeset || {}).first(3).map { |f, (a, b)| "#{change.model_label}の#{Audit.display_field_label(change, f)} #{a.inspect} → #{b.inspect}" }.join("、")
    end

    def milestone(op, change, who, at)
      cs = change.changeset || {}
      case change.auditable_type
      when "FiscalPeriod"
        year = change.snapshot&.dig("year") || change.record&.year
        if change.event == "create"
          SlackNotice.post!("ms-start-#{year}", "*#{year}年度を始めました* #{who} #{at}")
        elsif cs.key?("closed_at")
          closed = cs["closed_at"].last.present?
          SlackNotice.post!("ms-#{closed ? 'close' : 'reopen'}-#{year}-#{op.id}", "*#{year}年度を#{closed ? '締めました' : '締めを解きました'}* #{who} #{at}#{"\n理由: #{op.reason}" if !closed && op.reason.present?}")
        end
      when "ProcedureStep"
        step = change.record
        return unless step && cs["status"]&.last == "done"

        label = { "audit" => "監事の監査が済みました", "submit" => "所轄庁への提出を記録しました" }[step.key] or return
        SlackNotice.post!("ms-step-#{step.id}", "*#{label}* #{step.procedure_run.period_label}(#{step.procedure_run.name}) #{who} #{at}")
      when "AnnualReport"
        return unless cs["submitted_on"]&.last.present?

        year = change.record&.fiscal_year
        SlackNotice.post!("ms-submit-#{year}-#{cs['submitted_on'].last}", "*所轄庁への提出を記録しました* #{year}年度(提出日 #{cs['submitted_on'].last}) #{who} #{at}")
      end
    end
  end
end
