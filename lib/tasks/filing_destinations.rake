namespace :filing_destinations do
  desc "提出先を YAML から読み込む(実データは data/ に置く) 例: bin/rails 'filing_destinations:load[data/filing_destinations.yml]'"
  task :load, [:path] => :environment do |_, args|
    conf = YAML.load_file(args[:path] || "data/filing_destinations.yml", permitted_classes: [Date, Time])
    user = User.order(:id).first
    Audit.operation(user:, scope: "filing_destinations") do
      Audit.label!("提出先を読み込んだ")
      Array(conf["destinations"]).each_with_index do |row, i|
        d = FilingDestination.find_or_initialize_by(kind: row.fetch("kind"), name: row.fetch("name"))
        d.update!(row.slice(*FilingDestination::CONTENT_FIELDS, "notes").merge(origin: "human", position: i))
        next unless (c = row["confirmed"]) && !d.confirmed?

        FilingDestination::Confirmation.confirm!(d, by: user, at: Time.zone.parse(c.fetch("at").to_s))
      end
    end
    puts "提出先 #{FilingDestination.count} 件(確認済み #{FilingDestination.all.count(&:confirmed?)} 件)"
  end

  desc "法人情報の所轄庁(competent_authority)から、所轄庁の提出先を作る(まだ無いとき。宛先は空、確かめていない状態)"
  task from_organization: :environment do
    name = Organization.first&.competent_authority.to_s
    if name.blank? || FilingDestination.exists?(kind: "authority")
      puts "作るものはありません"
    else
      Audit.operation(user: User.order(:id).first, scope: "filing_destinations") do
        Audit.label!("法人情報の所轄庁から、提出先を作った")
        FilingDestination.create!(kind: "authority", name:, notes: "法人情報の所轄庁から移した。宛先と窓口を書いて確かめる")
      end
      puts "所轄庁 #{name} を提出先に作りました(確かめていない)"
    end
  end
end
