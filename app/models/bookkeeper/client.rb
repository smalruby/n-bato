module Bookkeeper
  # Claude API の呼び出し。JSON Schema で形を決めた答えを受け取る(structured outputs)。
  class Client
    MODEL = "claude-opus-5-5".freeze

    class Error < StandardError; end
    class NotConfigured < Error; end

    def self.api_key = ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key)
    def self.configured? = api_key.present?

    def model = MODEL

    # content: Messages API の content ブロックの配列。戻り値は JSON を読んだ Hash。
    def complete_json(system:, content:, schema:, max_tokens: 16_000)
      raise NotConfigured, "ANTHROPIC_API_KEY が設定されていません" unless self.class.configured?

      message = Anthropic::Client.new(api_key: self.class.api_key).messages.create(
        model: MODEL.to_sym,
        max_tokens: max_tokens,
        system_: [ { type: "text", text: system } ],
        messages: [ { role: "user", content: content } ],
        output_config: { format: { type: :json_schema, schema: schema } }
      )
      case message.stop_reason
      when :refusal then raise Error, "AI が回答を断りました"
      when :max_tokens then raise Error, "回答が長すぎて途中で切れました"
      end

      text = message.content.select { it.type == :text }.map(&:text).join
      JSON.parse(text)
    rescue Anthropic::Errors::APIError => e
      raise Error, "Claude API のエラー: #{e.message}"
    rescue JSON::ParserError => e
      raise Error, "AI の回答を JSON として読めません: #{e.message}"
    end
  end
end
