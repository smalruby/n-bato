# Slack に送った知らせ(同じものを二度送らないため)と、操作の記録をどこまで見たか(key = "cursor:audit")。
class CreateSlackPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_posts do |t|
      t.string :key, null: false
      t.text :text, null: false, default: ""
      t.datetime :posted_at
      t.timestamps
    end
    add_index :slack_posts, :key, unique: true
  end
end
