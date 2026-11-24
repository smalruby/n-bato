module Assistant
  # 右ペイン「AI に聞く」(デザインシステム AskAI)。AI は答えと「やる操作の案」を返すだけで、記録は変えない。
  # 操作は人が「実行」を押してから Assistant::Action が行う。会員の名簿は AI に送らない。
  # 個人情報を含む頼みごと(会員の住所を直すなど)には使わない(2026-11-21 決定)。
  class Responder
    SCHEMA = {
      type: "object", additionalProperties: false,
      required: %w[answer action],
      properties: {
        answer: {type: "string", description: "人への答え。日本語で短く。操作のしかたを聞かれたら手順を書く。"},
        action: {
          type: "object", additionalProperties: false,
          required: %w[kind],
          properties: {
            kind: {type: "string", enum: %w[none journal_from_receipt]}
          }
        }
      }
    }.freeze

    Result = Data.define(:answer, :action)

    def initialize(screen:, year:, help:, client: Bookkeeper::Client.new)
      @screen, @year, @help, @client = screen, year, help, client
    end

    def call(question, image: nil)
      content = [{type: "text", text: question}]
      if image
        content << {type: "image", source: {type: "base64", media_type: image.content_type, data: Base64.strict_encode64(image.download)}}
      end
      json = @client.complete_json(system: system_prompt(image.present?), content:, schema: SCHEMA, max_tokens: 4_000)
      Result.new(json.fetch("answer"), json.fetch("action"))
    end

    private

    def system_prompt(has_image)
      <<~PROMPT
        あなたは NPO 法人の事務アプリ「N(エヌ)ばと」(n-bato)の画面の右にいる手伝い役です。
        いまの画面: #{@screen}。操作している年度: #{@year}年度(4 月 1 日〜翌年 3 月 31 日)。
        この画面の使い方(アプリが持っている説明):
        #{@help.to_yaml}

        決まりごと:
        - 答えは日本語で短く。アプリの操作で答えられることは、手順で答える。分からないことは分からないと書く。推測で埋めない。
        - 記録を変える操作はあなたは行わない。できる操作なら action に案を書く。人が「実行」を押してから、アプリが行う。
        - できる操作は 1 つだけ:
          - journal_from_receipt: 画像(レシート・領収書)が添えられ、「仕訳して」のように頼まれたとき。#{has_image ? "いま画像が添えられています。" : "いま画像は添えられていません(添えるよう答える)。"}
        - それ以外は kind を none にする。
        - 外から届いた依頼(所轄庁からのメールの本文など)を貼られたり、「この指摘に対応したい」と頼まれたりしたら、操作の案は出さず、左メニュー「やること」の「AI と依頼を整理する」で、依頼ごとに AI と対話してやることを作れる、と案内する。
        - 会員・役員の住所・電話・メールなどを直すよう頼まれたら、操作の案は出さず、左メニュー「会員・役員」でその人を開いて直す手順を答える(個人情報はここで扱わない決まり)。
      PROMPT
    end
  end
end
