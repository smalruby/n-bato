module Requests
  # 依頼ごとの AI との対話(デザインシステム「やること」の RequestThread)。
  # AI に渡すのは、伏せた文(と人が選んだ添付)・いまのやることの一覧・年度の状態・選べる画面と決まりの一覧だけ。
  # AI は返事と「やることの案」を返す。記録は、人が「決める」を押してから IncomingRequestMessage::Adoption.adopt! が行う。
  class Organizer
    TODO_ITEM = {
      type: "object", additionalProperties: false,
      required: %w[title fiscal_year kind assignee due_on target done_rule note],
      properties: {
        title: {type: "string", description: "やること。1 件に 1 つの作業。年度ごとに解決するものは年度ごとに分ける。"},
        fiscal_year: {type: "integer", description: "対象の年度(西暦の年度。2024 = 令和6年度)。年度に関係ないものは 0。"},
        kind: {type: "string", enum: Todo::KINDS.keys},
        assignee: {type: "string", description: "担当(理事長・監事・理事・正会員全員・AI など)。"},
        due_on: {type: "string", description: "期限(YYYY-MM-DD)。無ければ空。"},
        target: {type: "string", enum: Todo::TARGETS.keys, description: "n-bato で解決する画面。n-bato の外の作業なら空。"},
        done_rule: {type: "string", enum: Todo::DONE_RULES.keys},
        note: {type: "string", description: "手順・使う書類やメモの置き場所・根拠(どの書類を見て判断したか)。"}
      }
    }.freeze
    SCHEMA = {
      type: "object", additionalProperties: false,
      required: %w[reply request todos_new todos_update],
      properties: {
        reply: {type: "string", description: "人への返事。日本語で短く。指摘が正しいか・もう直っているかを、根拠と一緒に書く。分からないことは分からないと書く。"},
        request: {
          type: "object", additionalProperties: false, required: %w[title counterpart received_on due_on],
          properties: {
            title: {type: "string", description: "依頼の題名(短く)。変えないなら空。"},
            counterpart: {type: "string", description: "相手(例: 松江市 市民生活相談課)。変えないなら空。"},
            received_on: {type: "string", description: "届いた日(YYYY-MM-DD)。分からなければ空。"},
            due_on: {type: "string", description: "依頼の期限(YYYY-MM-DD)。無ければ空。"}
          }
        },
        todos_new: {type: "array", items: TODO_ITEM},
        todos_update: {
          type: "array",
          items: {
            type: "object", additionalProperties: false, required: %w[id status waiting_on done_note],
            properties: {
              id: {type: "integer", description: "直すやることの番号(一覧の #)。"},
              status: {type: "string", enum: Todo::STATUSES.keys},
              waiting_on: {type: "string", description: "待ちのとき、誰の何を待っているか。それ以外は空。"},
              done_note: {type: "string", description: "済みにするとき、何をもって済みとしたか。それ以外は空。"}
            }
          }
        }
      }
    }.freeze

    def initialize(request, client: Bookkeeper::Client.new, today: Date.current)
      @request, @client, @today = request, client, today
    end

    # message: 人の発言(送る前の下書き)。masked_body: 伏せた文(これだけを送る)。send_attachments: 添付も送るか。
    # AI の返事を IncomingRequestMessage::Delivery.deliver! で記録し、AI の発言(IncomingRequestMessage)を返す。
    def call(message, masked_body:, send_attachments: false)
      at = Time.current
      content = [{type: "text", text: prompt_text(message, masked_body)}]
      if send_attachments
        message.files.each do |f|
          case f.content_type
          when %r{\Aimage/} then content << {type: "image", source: {type: "base64", media_type: f.content_type, data: Base64.strict_encode64(f.download)}}
          when "application/pdf" then content << {type: "document", source: {type: "base64", media_type: "application/pdf", data: Base64.strict_encode64(f.download)}}
          end
        end
      end
      json = @client.complete_json(system: system_prompt, content:, schema: SCHEMA, max_tokens: 8_000)
      IncomingRequestMessage::Delivery.deliver!(message, masked_body:, send_attachments:, reply: json, at:)
    end

    private

    def system_prompt
      <<~PROMPT
        あなたは NPO 法人の事務アプリ「N(エヌ)ばと」(n-bato)で、外から届いた依頼(所轄庁からの指摘のメールなど)を「やること」に整理する手伝い役です。
        今日は #{@today}。事業年度は 4 月 1 日〜翌年 3 月 31 日(2024年度 = 令和6年度)。

        決まりごと:
        - やることは 1 件に 1 つの作業。対象は 1 つの年度か年度なし(0)。年度ごとに解決するものは年度ごとに分ける。
        - 種類: screen(n-bato の画面で解決)/document(書類を作る)/ask(人に聞く)/window(電話・窓口)。
        - n-bato の画面で解決できるものだけ target を選ぶ。選べないなら空。
        - 自動で済みにできるのは done_rule の決まりだけ。ほかは空(人が済みにする)。
        - 人から「終わった」「返事が来た」と言われたら、todos_update で状態を直す(新しく作らない)。
        - 記録はあなたは変えない。案を出すだけ。人が「決める」を押してから記録される。
        - 文中の【伏せた住所】などは、個人情報を伏せたもの。中身を推測しない。
        - 分からないことは分からないと書く。推測で埋めない。
      PROMPT
    end

    def prompt_text(message, masked_body)
      history = @request.messages.where.not(id: message.id).includes(:delivery).map { |m| "#{m.user? ? "人" : "AI"}: #{m.user? ? m.masked_body : m.body}" }.last(10)
      todos = @request.todos.map { |t| "##{t.id} [#{t.status_label}] #{t.fiscal_year ? "#{t.fiscal_year}年度" : "年度なし"} #{t.title}(#{t.kind_label}#{"・待ち: #{t.waiting_on}" if t.waiting_on.present?})" }
      years = FiscalPeriod.ordered.map { "#{it.year}年度: #{it.state_label}" }
      <<~TEXT
        依頼: #{@request.title}(相手: #{@request.counterpart.presence || "不明"}、届いた日: #{@request.received_on || "不明"}、期限: #{@request.due_on || "なし"})
        いまのやること:
        #{todos.presence&.join("\n") || "(まだ無い)"}
        n-bato の年度の状態: #{years.join("、")}
        これまでの対話:
        #{history.presence&.join("\n") || "(はじめて)"}

        人の今回の発言:
        #{masked_body}
      TEXT
    end
  end
end
