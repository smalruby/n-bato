# やること(デザインシステム「やること」、見直し第9回)。年度ごとのデータセットの外に置く(年度をまたいで 1 つの一覧)。
class CreateIncomingRequestsAndTodos < ActiveRecord::Migration[8.1]
  def change
    # 外から届いた依頼(松江市のメールなど)。やることは、依頼ごとの AI との対話で作る。
    create_table :incoming_requests do |t|
      t.string :title, null: false, default: "(整理中の依頼)"
      t.string :counterpart, null: false, default: ""   # 相手(松江市 市民生活相談課 など)
      t.date :received_on
      t.date :due_on
      t.string :status, null: false, default: "open"   # open / resolved
      t.date :resolved_on
      t.text :cover_letter                                # 解決したときの送付状・返信の下書き
      t.timestamps
    end

    # 依頼ごとの対話。人の発言は伏せた文(masked_body)だけを AI に送る。AI の案(proposal)は人が決めてから記録する。
    create_table :incoming_request_messages do |t|
      t.references :incoming_request, null: false, foreign_key: true
      t.string :role, null: false                         # user / assistant
      t.text :body, null: false, default: ""              # 人が書いたまま(AI には送らない)
      t.text :masked_body, null: false, default: ""       # 伏せた文(AI に送る)
      t.boolean :send_attachments, null: false, default: false
      t.datetime :sent_at                                 # AI に送った日時(送るまでは下書き)
      t.json :proposal                                    # AI の案
      t.datetime :applied_at                              # 人が「決める」を押した日時
      t.timestamps
    end

    create_table :todos do |t|
      t.references :incoming_request, foreign_key: true  # 依頼から作ったもの(義務・手続きは n-bato が自動で出すので、ここには入れない)
      t.integer :position, null: false, default: 0
      t.string :title, null: false
      t.integer :fiscal_year                              # 対象の年度。nil は年度なし
      t.string :kind, null: false, default: "screen"      # screen / document / ask / window
      t.string :assignee, null: false, default: ""
      t.string :status, null: false, default: "todo"      # todo / doing / wait / done
      t.string :waiting_on, null: false, default: ""
      t.date :due_on
      t.string :target, null: false, default: ""          # 開く画面(Todo::TARGETS のキー)
      t.text :note, null: false, default: ""              # 手順・使う書類やメモの置き場所
      t.string :done_rule, null: false, default: ""       # 自動で済みにする決まり(Todo::DONE_RULES のキー)
      t.datetime :done_at
      t.string :done_by, null: false, default: ""         # user / auto
      t.string :done_note, null: false, default: ""
      t.timestamps
    end
    add_index :todos, %i[status fiscal_year]
  end
end
