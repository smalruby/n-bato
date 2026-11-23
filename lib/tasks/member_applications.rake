# 入会申込を入れる(AI が Google フォームの回答から作った JSON を読む)。同じ回答(source_key)は二度入れない。
#   bin/rails member_applications:import FILE=path/to/applications.json
# JSON は配列。項目: source_key, applied_on, name, name_kana, age_group, postal_code, address, email, phone,
#   notice_method, materials_method, referral, help_offers, comments
namespace :member_applications do
  desc "入会申込を JSON から入れる(FILE=...)"
  task import: :environment do
    file = ENV.fetch("FILE") { abort "FILE=... を指定してください" }
    rows = JSON.parse(File.read(file))
    keys = MemberApplication.column_names - %w[id status fiscal_year joined_on decided_on reason person_id created_at updated_at source]
    added = 0
    Audit.operation(user: User.first, scope: "member_applications") do
      Audit.label!("入会申込をフォームの回答から入れた")
      rows.each do |r|
        next if r["source_key"].present? && MemberApplication.exists?(source_key: r["source_key"])

        MemberApplication.create!(r.slice(*keys))
        added += 1
      end
    end
    puts "入会申込を #{added} 件入れました(すでにあったもの #{rows.size - added} 件)"
  end
end
