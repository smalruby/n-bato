---
status: 採用
date: 2026-11-23
decision-makers: 理事長(ユーザー)・Claude
---

# ADR を日本語の MADR で残す

## 状況と問題

設計の大事な決定(なぜそうしたか・何をやめたか)が、会話や手元の記録に散らばっている。n-bato は AI が設計・実装し、人が合意して進める。次に読む人(人も AI も)が、決めた理由と退けた案を追えるようにしたい。

## 判断の基準

* 退けた選択肢と、その理由が残ること
* 人にも AI にも読みやすい形(節に分かれていること)
* n-bato は日本の NPO 法人の事務のためのもので、日本でしか使わない

## 検討した選択肢

* Nygard 形式(状況・決定・結果だけの短い形)
* Y-Statements(1 文で書く形)
* MADR 4.0(Markdown Any Decision Records)を日本語にしたもの

## 決定

採用:「MADR 4.0 を日本語にしたもの」。理由: 検討した選択肢と判断の基準を書く節があり、退けた案と理由が残る。節に分かれているので、人も AI も段階的に読める。日本でしか使わないので、見出しも本文も日本語にする。

### 結果

* 良い: 決めた理由と退けた案が、リポジトリの中に残る。
* 悪い: 書く手間が増える。すべての節を埋めなくてよい(要る節だけ使う)。

### 確かめ方

設計に関わる合意(見直し票の回の答えなど)のたびに、docs/adr/ に足す。CLAUDE.md から参照する。

## 補足

* 見出しの対応: Context and Problem Statement → 状況と問題、Decision Drivers → 判断の基準、Considered Options → 検討した選択肢、Decision Outcome → 決定、Consequences → 結果、Confirmation → 確かめ方、Pros and Cons of the Options → 選択肢ごとの良い点と悪い点、More Information → 補足。Good / Neutral / Bad → 良い / どちらでもない / 悪い。
* 状態: 提案中 → 採用 / 却下。あとで覆したら「ADR-NNNN で置き換え」、やめたら「廃止」。
* 出どころ: MADR(https://github.com/adr/madr)。MADR を元に要る節だけ使う運用は、Qiita の記事(https://qiita.com/betsu6419/items/df2d15c56ffad909ca1c)を参考にした。
