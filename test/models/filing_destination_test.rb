require "test_helper"

# 提出先(見直し第17回、docs/adr/0027・0028)
class FilingDestinationTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :prompt
    def initialize(result = nil, error: nil) = (@result, @error = result, error)

    def search_json(system:, prompt:, schema:)
      @prompt = prompt
      raise @error if @error

      @result
    end
  end

  def authority(**attrs) = FilingDestination.create!(kind: "authority", name: "テスト市", addressee: "テスト市長　山田　太郎", **attrs)

  test "確かめるまでは宛先にも説明にも使わない。確かめたら使い、直すと確認済みでなくなる" do
    d = authority
    assert_equal FilingDestination::UNSET_ADDRESSEE, FilingDestination.letter_addressee
    assert_equal "(所轄庁が未設定)に出す", FilingDestination.fill("{所轄庁}に出す")
    assert_nil FilingDestination.fill(nil)
    assert_equal "そのまま", FilingDestination.fill("そのまま")
    assert_equal "まだ確かめていない", d.state_label

    FilingDestination::Confirmation.confirm!(d, by: users(:one))
    assert d.reload.confirmed?
    assert_equal "テスト市長　山田　太郎", FilingDestination.letter_addressee
    assert_equal ["テスト市に出す", ["様式", "テスト市の作成例"]], FilingDestination.fill(["{所轄庁}に出す", ["様式", "{所轄庁}の作成例"]])
    assert_equal "確認済み", d.state_label

    d.update!(addressee: "テスト市長　山田　次郎")
    assert_not d.reload.confirmed?
    assert_equal "直したあと、まだ確かめていない", d.state_label
    assert_equal FilingDestination::UNSET_ADDRESSEE, FilingDestination.letter_addressee
  end

  test "所轄庁は名前と宛先が空だと確かめられない" do
    d = FilingDestination.create!(kind: "authority", name: "テスト市")
    assert_raises(ArgumentError) { FilingDestination::Confirmation.confirm!(d, by: users(:one)) }
  end

  test "手続きの説明の {所轄庁} を差し込む" do
    FilingDestination::Confirmation.confirm!(authority, by: users(:one))
    step = ProcedureDefinition.find("annual_report").steps.find { it.title.end_with?("に出す") }
    assert_equal "テスト市に出す", step.title
    assert_includes ProcedureDefinition.find("annual_report").summary, "テスト市に出します"
  end

  test "AI の調べもの: 所在地だけを送り、出どころのある案を「AI の案」として足す" do
    result = {"destinations" => [
      {"kind" => "authority", "name" => "テスト市", "addressee" => "", "office" => "市民課", "address" => "", "phone" => "", "fax" => "", "email" => "", "hours" => "",
       "forms_url" => "", "source" => "https://example.jp/npo", "notes" => "市内だけに事務所がある法人の担当"},
      {"kind" => "tax_office", "name" => "テスト税務署", "addressee" => "", "office" => "", "address" => "", "phone" => "", "fax" => "", "email" => "", "hours" => "",
       "forms_url" => "", "source" => ""}
    ]}
    client = FakeClient.new(result)
    search = FilingDestinationSearch.create!(address: "テスト県テスト市1-1", requested_at: Time.current)
    search.run!(client:)
    assert_includes client.prompt, "テスト県テスト市1-1"
    assert_equal "done", search.reload.status
    assert_equal 1, search.found_count, "出どころの無い案は足さない"
    d = FilingDestination.last
    assert d.ai? && !d.confirmed?
    assert_equal "AI の案(人が確かめる)", d.state_label
    assert_match "市内だけに事務所がある法人の担当", d.notes
  end

  test "AI の調べもの: 行のある種類は調べさせず、案も足さない(見直し第19回)" do
    authority # 確かめていなくても、行があれば調べない
    assert_not_includes FilingDestination.missing_kinds, "authority"
    assert_includes FilingDestination.missing_kinds, "registry"
    row = ->(kind, name) {
      {"kind" => kind, "name" => name, "addressee" => "", "office" => "", "address" => "", "phone" => "", "fax" => "", "email" => "",
       "hours" => "", "forms_url" => "", "source" => "https://example.jp/#{kind}", "notes" => ""}
    }
    client = FakeClient.new({"destinations" => [row.call("authority", "テスト市"), row.call("registry", "テスト法務局")]})
    search = FilingDestinationSearch.create!(address: "テスト県テスト市1-1", requested_at: Time.current)
    search.run!(client:)
    assert_includes client.prompt, "調べなくてよい種類(すでにある): 所轄庁(NPO 法人の担当)"
    assert_equal 1, search.reload.found_count
    assert_equal 1, FilingDestination.where(kind: "authority").count, "すでにある所轄庁と重なる案は足さない"
    assert_equal "テスト法務局", FilingDestination.where(origin: "ai").sole.name
  end

  test "AI の調べものが失敗したら failed にして理由を残す" do
    search = FilingDestinationSearch.create!(address: "テスト市", requested_at: Time.current)
    search.run!(client: FakeClient.new(error: Bookkeeper::Client::Error.new("Claude API のエラー")))
    assert_equal "failed", search.reload.status
    assert_match "Claude API", search.error_message
    assert_equal "調べられませんでした", search.status_label
  end
end
