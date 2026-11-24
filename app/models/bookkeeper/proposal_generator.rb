module Bookkeeper
  # 証憑から仕訳を提案する。科目表・部門・過去の似た仕訳を渡し、会計王の科目コードで答えてもらう。
  class ProposalGenerator
    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[entries questions],
      properties: {
        entries: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[entry_date debit_account_code debit_department_code credit_account_code credit_department_code amount summary sub_summary rationale confidence],
            properties: {
              entry_date: {type: "string", format: "date", description: "取引日 YYYY-MM-DD"},
              debit_account_code: {type: "integer"},
              debit_department_code: {type: "integer", description: "部門コード。部門なしは 0"},
              credit_account_code: {type: "integer"},
              credit_department_code: {type: "integer", description: "部門コード。部門なしは 0"},
              amount: {type: "integer", description: "金額(円、税込)"},
              summary: {type: "string", description: "取引摘要(過去の仕訳の書き方に合わせる)"},
              sub_summary: {type: "string", description: "補助摘要(品名・相手など)"},
              rationale: {type: "string", description: "この科目・部門にした理由(日本語、1〜3 文)"},
              confidence: {type: "string", enum: %w[high medium low]}
            }
          }
        },
        questions: {type: "array", items: {type: "string"}, description: "人に確かめたいこと(無ければ空)"}
      }
    }.freeze

    def initialize(voucher, client: Client.new)
      @voucher = voucher
      @client = client
    end

    def call
      @voucher.update!(status: "proposing", ai_error: nil)
      apply(@client.complete_json(system: system_prompt, content: content_blocks, schema: SCHEMA), model: @client.model)
    rescue Client::Error => e
      @voucher.update!(status: "error", ai_error: e.message.truncate(250))
      []
    end

    # AI の答え(SCHEMA の形の Hash)から提案を作る。API を使わず、手元の Claude Code が作った JSON にも使う。
    def apply(result, model:)
      @model = model
      proposals = JournalProposal.transaction do
        @voucher.journal_proposals.pending.each { JournalProposal::Withdrawal.withdraw!(it) }
        result.fetch("entries").map { propose(it) }
      end
      @voucher.update!(status: proposals.any? ? "proposed" : "pending", ai_error: nil, ai_questions: Array(result["questions"]).join("\n"))
      proposals
    rescue KeyError, ActiveRecord::RecordInvalid, ArgumentError => e
      @voucher.update!(status: "error", ai_error: e.message.truncate(250))
      []
    end

    def system_prompt
      org = Organization.current
      <<~PROMPT
        あなたは #{org.name} の経理担当です。NPO 法人会計基準に沿って、渡された証憑(領収書・通帳・メモなど)から仕訳を作ります。
        帳簿は会計ソフト「会計王」で管理しており、あなたの仕訳は人が確認・承認してから会計王に取り込みます。

        決まりごと:
        - 1 件の仕訳は借方・貸方とも 1 科目。金額は税込の円(整数)。
        - 科目・部門は、下の一覧にあるコードだけを使う。
        - 事業に使った費用は「(事業)」の付いた科目にし、借方の部門に事業の区分(①〜⑨)を入れる。法人の運営のための費用は管理費の科目にし、部門は管理部門(900)にする。
        - 収益の貸方の部門は、会費は管理部門、事業の収益・寄付はその事業の部門にする(過去の仕訳に合わせる)。
        - 現金・預金など貸借対照表の科目の部門は 0(なし)。
        - 摘要の書き方は過去の仕訳に合わせる(例: 「消耗品を買った」、補助摘要に品名)。
        - 証憑から読み取れないこと、判断に迷うことは推測で埋めず、questions に書く。読み取れない証憑なら entries を空にする。
        - 1 枚の証憑に複数の取引があれば、複数の仕訳にする。

        事業年度は 4 月 1 日から翌年 3 月 31 日。

        ## 科目(コード: 名前 [区分])
        #{Account.in_year(dataset_year).ordered.map { "#{it.code}: #{it.display_name} [#{it.category_label}#{" / #{it.activity_group}" if it.activity?}]" }.join("\n")}

        ## 部門(コード: 名前 — 主な活動)
        どの事業かは、主な活動(法人が書いた、いまの活動)で判断する。
        0: なし
        #{Department.in_year(dataset_year).ordered.map { "#{it.code}: #{it.long_name}#{" — #{activities[it.code]}" if activities[it.code]}" }.join("\n")}

        ## 過去の仕訳の例(新しい順)
        #{examples}
      PROMPT
    end

    def content_blocks
      blocks = @voucher.files.map do |file|
        data = Base64.strict_encode64(file.download)
        if file.content_type == "application/pdf"
          {type: "document", source: {type: "base64", media_type: "application/pdf", data: data}}
        else
          {type: "image", source: {type: "base64", media_type: file.content_type, data: data}}
        end
      end
      text = "証憑の種類: #{@voucher.kind_label}\n"
      text << "日付(人が入力): #{@voucher.issued_on}\n" if @voucher.issued_on
      text << "金額(人が入力): #{@voucher.amount} 円\n" if @voucher.amount
      text << "説明(人が入力): #{@voucher.description}\n" if @voucher.description.present?
      text << "補足: #{@voucher.notes}\n" if @voucher.notes.present?
      text << "\nこの証憑の仕訳を提案してください。"
      blocks << {type: "text", text: text}
    end

    private

    def examples
      JournalEntry.active.includes(:debit_account, :credit_account, :debit_department, :credit_department)
        .order(entry_date: :desc).limit(40).map do |e|
        "#{e.entry_date} 借方 #{e.debit_account.code} #{e.debit_account.display_name}#{"(#{e.debit_department.code})" if e.debit_department} / " \
          "貸方 #{e.credit_account.code} #{e.credit_account.display_name}#{"(#{e.credit_department.code})" if e.credit_department} " \
          "#{e.amount}円 摘要「#{e.summary}」#{"補助「#{e.sub_summary}」" if e.sub_summary.present?}"
      end.join("\n").presence || "(まだありません)"
    end

    def propose(item)
      JournalProposal.propose!(
        voucher: @voucher, model: @model || @client.model,
        entry_date: Date.iso8601(item.fetch("entry_date")),
        debit_account: Account.in_year(FiscalYear.for(Date.iso8601(item.fetch("entry_date"))).year).find_by!(code: item.fetch("debit_account_code")),
        debit_department: department(item.fetch("debit_department_code"), item.fetch("entry_date")),
        credit_account: Account.in_year(FiscalYear.for(Date.iso8601(item.fetch("entry_date"))).year).find_by!(code: item.fetch("credit_account_code")),
        credit_department: department(item.fetch("credit_department_code"), item.fetch("entry_date")),
        amount: item.fetch("amount"),
        summary: item.fetch("summary"), sub_summary: item.fetch("sub_summary"),
        rationale: item.fetch("rationale"), confidence: item.fetch("confidence")
      )
    rescue ActiveRecord::RecordNotFound => e
      raise ArgumentError, "AI が一覧に無いコードを使いました（#{e.message}）"
    end

    def department(code, date) = code.to_i.zero? ? nil : Department.in_year(FiscalYear.for(Date.iso8601(date)).year).find_by!(code: code)

    # 一覧に出す科目・部門の年度(証憑の日付の年度。無ければ操作している年度)
    def activities = @activities ||= ProgramProfile.activities_by_code

    def dataset_year = (@voucher.try(:issued_on) && FiscalYear.for(@voucher.issued_on).year) || Current.working_year || FiscalYear.current.year
  end
end
