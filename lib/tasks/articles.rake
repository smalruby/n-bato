namespace :articles do
  desc "定款の版と事業ごとの主な活動を YAML から読み込む(実データは data/ に置く) 例: bin/rails 'articles:load[data/articles.yml]'"
  task :load, [:path] => :environment do |_, args|
    path = Pathname(args[:path] || "data/articles.yml")
    conf = YAML.load_file(path, permitted_classes: [Date])
    Audit.operation(user: User.first, scope: "articles", label: "定款の版と主な活動を読み込んだ") do
      Array(conf["versions"]).each do |h|
        v = ArticleVersion.find_or_initialize_by(number: h.fetch("number"))
        body = h["body_file"] ? path.dirname.join(h["body_file"]).read : h.fetch("body", "")
        v.update!(h.except("number", "body_file", "body").merge("body" => body))
      end
      (conf["programs"] || {}).each { |code, text| ProgramProfile.for(code).update!(activities: text.to_s) }
    end
    puts "定款の版 #{ArticleVersion.count} 件、主な活動 #{ProgramProfile.where.not(activities: "").count} 件"
  end
end
