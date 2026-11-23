# 定款の版(見直し第13回)と、事業ごとの主な活動。どちらも年度に依存しない。
class CreateArticleVersionsAndProgramProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :article_versions do |t|
      t.integer :number, null: false
      t.date :decided_on, null: false
      t.string :meeting, null: false, default: ""          # 決めた会議(例: 通常総会 第6号議案)
      t.string :resolution, null: false, default: ""       # 議決(例: 満場一致)
      t.string :authority, null: false, default: ""        # 所轄庁(認証・届出とその日。不明なら不明と書く)
      t.string :changed_articles, null: false, default: "" # 変わった条
      t.text :reason, null: false, default: ""
      t.string :source, null: false, default: ""           # 原本の置き場所
      t.text :body, null: false, default: ""               # 全文(Markdown)
      t.timestamps
    end
    add_index :article_versions, :number, unique: true

    create_table :program_profiles do |t|
      t.integer :code, null: false                         # 部門コード(111〜119 = ①〜⑨、900 = 管理)
      t.text :activities, null: false, default: ""         # 主な活動(人が書く)
      t.timestamps
    end
    add_index :program_profiles, :code, unique: true
  end
end
