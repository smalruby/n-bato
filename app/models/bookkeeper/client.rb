module Bookkeeper
  # Claude API の呼び出し。JSON Schema で形を決めた答えを受け取る(structured outputs)。
  class Client
    MODEL = "claude-opus-5-5".freeze

    class Error < StandardError; end
    class NotConfigured < Error; end

    def self.api_key = ENV["ANTHROPIC_API_KEY"].presence || Rails.application.credentials.dig(:anthropic, :api_key)
    def self.configured? = api_key.present?

    # api: Anthropic::Client の代わり。テストでは偽の API を渡すか、Bookkeeper::Client.api に入れる
    # (SlackNotice.poster と同じ。本物の Claude API は呼ばない)。nil なら本物を使う。
    class << self
      attr_accessor :api
    end

    def initialize(api: self.class.api) = @api = api

    def model = MODEL

    # content: Messages API の content ブロックの配列。戻り値は JSON を読んだ Hash。
    def complete_json(system:, content:, schema:, max_tokens: 16_000)
      raise NotConfigured, "ANTHROPIC_API_KEY が設定されていません" unless self.class.configured?

      message = api.messages.create(
        model: MODEL.to_sym,
        max_tokens: max_tokens,
        system_: [{type: "text", text: system}],
        messages: [{role: "user", content: content}],
        output_config: {format: {type: :json_schema, schema: schema}}
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

    # Web 検索(サーバーツール web_search_20260209)を使って調べ、JSON Schema の形で答えを受け取る(提出先の調べもの。docs/adr/0028)。
    # 外部連携なので、実際の呼び出しは人と一緒に確かめてから使い始める。自動テストでは偽の API(FakeClaudeApi)で確かめる。
    def search_json(system:, prompt:, schema:, max_tokens: 16_000, max_uses: 8)
      raise NotConfigured, "ANTHROPIC_API_KEY が設定されていません" unless self.class.configured?

      messages = [{role: "user", content: prompt}]
      message = nil
      5.times do
        message = api.messages.create(
          model: MODEL.to_sym, max_tokens: max_tokens, system_: [{type: "text", text: system}], messages: messages,
          tools: [{type: "web_search_20260209", name: "web_search", max_uses: max_uses}],
          output_config: {format: {type: :json_schema, schema: schema}}
        )
        break unless message.stop_reason == :pause_turn

        messages += [{role: "assistant", content: message.content.map(&:to_h)}] # 長い検索の途中で止まったら、続きを頼む
      end
      case message.stop_reason
      when :refusal then raise Error, "AI が回答を断りました"
      when :max_tokens then raise Error, "回答が長すぎて途中で切れました"
      end
      text = message.content.select { it.type == :text }.map(&:text).join
      JSON.parse(text[/\{.*\}/m] || text)
    rescue Anthropic::Errors::APIError => e
      raise Error, "Claude API のエラー: #{e.message}"
    rescue JSON::ParserError => e
      raise Error, "AI の回答を JSON として読めません: #{e.message}"
    end

    private

    def api = @api ||= Anthropic::Client.new(api_key: self.class.api_key)
  end
end
