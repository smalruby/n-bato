# パスキー(WebAuthn、見直し第14回)。1 人が複数持てる。公開鍵だけを持ち、秘密の鍵は端末から出ない。
class CreatePasskeys < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :webauthn_id, :string
    add_index :users, :webauthn_id, unique: true
    # 最後に本人を確かめた時(ログイン、または確かめ直し)。パスキーを足す・消す前の 10 分の判定に使う。
    add_column :sessions, :verified_at, :datetime

    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false   # 資格情報の ID(base64url)
      t.text :public_key, null: false      # 公開鍵(COSE、base64url)
      t.integer :sign_count, null: false, default: 0
      t.string :name, null: false, default: ""
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :passkeys, :external_id, unique: true
  end
end
