# 提出先を AI に調べてもらう(長いイベント。日時は requested_at、いまの状態は status)。docs/adr/0028
# 送るのは法人の所在地と法人の種類だけ(会員の情報は送らない)。見つけた窓口は「AI の案」として提出先に足し、人が確かめるまで書類には使わない。
class FilingDestinationSearch < ApplicationRecord
  STATUSES = {"searching" => "調べています", "done" => "調べ終わりました", "failed" => "調べられませんでした"}.freeze
  ORG_KIND = "特定非営利活動法人(NPO 法人)".freeze

  belongs_to :requested_by, class_name: "User", optional: true

  validates :address, presence: true
  validates :status, inclusion: {in: STATUSES.keys}

  SCHEMA = {
    type: "object", additionalProperties: false, required: %w[destinations],
    properties: {
      destinations: {
        type: "array",
        items: {
          type: "object", additionalProperties: false,
          required: %w[kind name addressee office address phone fax email hours forms_url source notes],
          properties: {
            kind: {type: "string", enum: FilingDestination::KINDS.keys},
            name: {type: "string", description: "機関の名前(例: ○○市、○○県○○県税事務所、○○地方法務局、○○税務署)"},
            addressee: {type: "string", description: "書類の宛先(役職と氏名。例: ○○市長　氏　名)。分からなければ空"},
            office: {type: "string", description: "担当の窓口の部・課・係の名前だけ(例: 市民部 市民生活相談課)。説明は notes に書く"},
            address: {type: "string"}, phone: {type: "string"}, fax: {type: "string"}, email: {type: "string"},
            hours: {type: "string", description: "受付の時間"},
            forms_url: {type: "string", description: "様式・手引きのページの URL"},
            source: {type: "string", description: "この情報を確かめたページの URL(必須)"},
            notes: {type: "string", description: "補足(受け持つ区域・郵送先・所轄の決まり方など)。無ければ空"}
          }
        }
      }
    }
  }.freeze

  def self.latest = order(:requested_at, :id).last
  def searching? = status == "searching"
  def status_label = STATUSES[status]

  # 調べてもらうのを頼む(作る入口)。調べるのは裏の仕事(FilingDestinationSearchJob)。
  def self.request!(address:, by:, at: Time.current)
    create!(address: address.to_s.strip, requested_by: by, requested_at: at).tap do |search|
      Audit.label!("提出先を AI に調べてもらうよう頼んだ")
      FilingDestinationSearchJob.perform_later(search)
    end
  end

  # 調べる。client は complete と同じ形の search_json を持つもの(テストでは偽物)。
  def run!(client: Bookkeeper::Client.new)
    result = client.search_json(system: system_prompt, prompt: prompt, schema: SCHEMA)
    found = Array(result["destinations"]).select { it["source"].present? && it["name"].present? }
      .reject { existing_kinds.include?(it["kind"]) }
    transaction do
      found.each do |d|
        notes = ["AI が #{requested_at.to_date} に調べた案(人が確かめる)", d["notes"].presence].compact.join("。")
        FilingDestination.create!(d.slice(*FilingDestination::CONTENT_FIELDS).merge(origin: "ai", notes: notes))
      end
      update!(status: "done", found_count: found.size)
    end
  rescue Bookkeeper::Client::Error => e
    update!(status: "failed", error_message: e.message)
  end

  # 行が 1 件でもある種類。重ならないよう、調べず、案も足さない(見直し第19回: 確かめていない行があっても調べ直さない)。
  def existing_kinds
    @existing_kinds ||= FilingDestination.existing_kinds
  end

  def system_prompt = <<~TEXT
    日本の NPO 法人の事務を手伝う役として、法人の所在地から、書類を出す先の役所の窓口を Web 検索で調べる。
    - 調べる先: 所轄庁(NPO 法人の認証・事業報告書等の提出先。法人の主たる事務所がある市町村、または都道府県)、法人住民税(県)の窓口(県税事務所)、法人住民税(市町村)の窓口、登記(法務局)、税務署。
    - 公式のページ(自治体・法務局・国税庁など)で確かめたものだけを書き、source にそのページの URL を書く。確かめられないものは書かない。
    - 推測で埋めない。分からない項目は空の文字にする。首長の氏名(宛先)は、公式のページで確かめられたときだけ書く。
    - office には部・課・係の名前だけを書く。説明(受け持つ区域・郵送先・所轄の決まり方など)は notes に短く書く。
    - 「調べなくてよい種類」に挙げた種類は、調べず、書かない。
  TEXT

  def prompt
    skip = existing_kinds.map { FilingDestination::KINDS[it] }
    ["法人の種類: #{ORG_KIND}", "主たる事務所の所在地: #{address}",
      ("調べなくてよい種類(すでにある): #{skip.join("、")}" if skip.any?),
      "この法人が書類を出す先の窓口を調べてください。"].compact.join("\n")
  end
end
