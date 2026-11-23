# 長いイベントの「いまの状態」が、詳細のイベントから作り直した状態と一致するかを確かめる(docs/adr/0005)。
# bin/rails model:verify で流す(CI と手元のデータ)。長いイベントを移したら、ここに照合を足す。
module ModelVerification
  module_function

  # 食い違いの一覧(文字列)。空なら一致。
  def mismatches
    voucher_mismatches
  end

  def voucher_mismatches
    Voucher.includes(:journal_proposals).filter_map do |v|
      derived = v.derived_status
      "証憑 ##{v.id}: いまの状態 #{v.status} / イベントから #{derived}" unless v.status == derived
    end
  end
end
