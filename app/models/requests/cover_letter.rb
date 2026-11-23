module Requests
  # 依頼のやることが全部済んだら、送付状(または返信)の下書きを作る。送るのは人。
  class CoverLetter
    SCHEMA = { type: "object", additionalProperties: false, required: %w[text], properties: { text: { type: "string" } } }.freeze

    def initialize(request, client: Bookkeeper::Client.new) = (@request, @client = request, client)

    def call
      todos = @request.todos.map { "- #{it.fiscal_year ? "#{it.fiscal_year}年度 " : ''}#{it.title}(#{it.done_note.presence || it.status_label})" }
      org = Organization.current
      text = <<~TEXT
        依頼: #{@request.title}(相手: #{@request.counterpart}、届いた日: #{@request.received_on})
        対応したこと:
        #{todos.join("\n")}
        差出人: #{org&.name} 理事長
        依頼の文面(個人情報は伏せてある):
        #{@request.messages.select(&:user?).first&.masked_body}
      TEXT
      json = @client.complete_json(system: "NPO 法人の事務の手伝い役として、相手への送付状(書類を出すときの添え状)か返信メールの下書きを日本語で作る。依頼の番号や項目に沿って、何をどう直したかを書く。お詫びは簡潔に。推測で事実を足さない。日付は空欄にする。", content: [ { type: "text", text: } ], schema: SCHEMA, max_tokens: 4_000)
      @request.update!(cover_letter: json.fetch("text"))
      @request.cover_letter
    end
  end
end
