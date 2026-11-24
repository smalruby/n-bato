# いまは使えない操作の理由(デザインシステム DisabledAction、見直し第22回)。
# 画面の (i) の説明・運用のスクリプト・モデルのエラーの文(消そうとして止めたときなど)で、同じ文を使うためにモデルが返す。
#
#   title       なぜ使えないか(見出し)。例「この決議は消せません」
#   reason      その決まりの文(句点で終える)。例「書面決議の記録として残すため、同意を記録した決議は消せません。」
#   what        何があるか(件数など。句点なし)。例「同意の記録が 3 件あります(取り消した 1 件を含む)」
#   link_label  それを見るリンクの文。例「同意の記録を見る(3 件)」
#   link_target リンク先。"#consents" のような同じ画面の場所か、記録(画面が url_for で道筋にする)
#   alternative 代わりにできること(いまある操作でできるときだけ。句点で終える)。例「代わりに: …は「編集」で直せます。」
BlockedReason = Data.define(:title, :reason, :what, :link_label, :link_target, :alternative) do
  def initialize(title:, reason:, what: nil, link_label: nil, link_target: nil, alternative: nil) = super

  # 1 つの文にしたもの(エラーの文・運用のスクリプト・画面の上の知らせ)
  def message = [ "#{title}。", what&.then { "#{it}。" }, reason, alternative ].compact.join
  alias_method :to_s, :message

  def link? = link_label.present? && link_target.present?
end
