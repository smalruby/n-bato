module Assistant
  # AI が出した「やる操作の案」。人が「実行」を押したら行う(操作履歴に残り、元に戻せる)。
  # 案は署名して画面に渡し、書き換えられないようにする。
  # 会員の記録を直す案は出さない(2026-11-21 決定: 個人情報を含む頼みごとには AI に聞くを使わない。人の画面で直す)。
  class Action
    def self.verifier = Rails.application.message_verifier("assistant-action")

    # 案を作る。実行できない案なら [nil, 理由]
    def self.prepare(raw, year:, image_blob: nil)
      case raw["kind"]
      when "journal_from_receipt"
        return [nil, "画像を添えてください"] unless image_blob
        return [nil, "画像（JPEG・PNG など）か PDF を添えてください"] unless Voucher::ACCEPTED_TYPES.include?(image_blob.content_type)

        payload = {"kind" => "journal_from_receipt", "blob" => image_blob.signed_id, "year" => year}
        [{label: "この画像を証憑として登録し、AI 仕訳の案を作る(承認は証憑の画面で)", token: verifier.generate(payload), reason_required: false}, nil]
      else
        [nil, nil]
      end
    end

    # 実行する。戻り値は [メッセージ, 移る先]
    def self.perform(token, reason: nil)
      payload = verifier.verify(token)
      case payload["kind"]
      when "journal_from_receipt"
        blob = ActiveStorage::Blob.find_signed!(payload["blob"])
        voucher = Voucher.create!(kind: "receipt", description: "AI に聞く から登録", files: [blob]) # ファイルを確かめてから作る(断ったら証憑を残さない)
        Audit.label!("AI に頼んだ: 証憑を登録して仕訳の案を作った")
        Bookkeeper::ProposalGenerator.new(voucher).call
        ["証憑を登録し、仕訳の案を作りました。証憑の画面で確かめて承認してください", Rails.application.routes.url_helpers.voucher_path(voucher)]
      end
    end
  end
end
