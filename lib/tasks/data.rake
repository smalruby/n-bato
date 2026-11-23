namespace :data do
  desc "会員・役員・事業報告書を YAML から読み込む(実データは data/ に置く) 例: bin/rails 'data:load[data/records.yml]'"
  task :load, [ :path ] => :environment do |_, args|
    conf = YAML.load_file(args.fetch(:path), permitted_classes: [ Date ])
    ActiveRecord::Base.transaction do
      people = Array(conf["people"]).to_h do |h|
        person = Person.find_or_initialize_by(name: h.fetch("name"))
        person.update!(h.slice("name_kana", "address", "email", "phone", "notes").compact)
        [ person.name, person ]
      end
      Array(conf["memberships"]).each do |h|
        Array(h.fetch("names")).each do |name|
          Membership.find_or_create_by!(person: people.fetch(name), fiscal_year: h.fetch("fiscal_year"), kind: h.fetch("kind", "regular"))
        end
      end
      Array(conf["officer_terms"]).each do |h|
        term = OfficerTerm.find_or_initialize_by(person: people.fetch(h.fetch("name")), role: h.fetch("role"), starts_on: h.fetch("starts_on"))
        term.update!(h.slice("ends_on", "left_on", "remunerated", "appointed_by", "notes").compact)
      end
      Array(conf["annual_reports"]).each do |h|
        report = AnnualReport.find_or_initialize_by(fiscal_year: h.fetch("fiscal_year"))
        report.update!(h.except("fiscal_year", "programs"))
        Array(h["programs"]).each_with_index do |p, i|
          dept = Department.in_year(report.fiscal_year).find_by!(code: p.fetch("department_code"))
          pa = report.program_activities.find_or_initialize_by(department: dept)
          pa.update!(p.except("department_code").merge("position" => i))
        end
      end
      Array(conf["past_submissions"]).each do |h|
        AnnualReport.find_or_initialize_by(fiscal_year: h.fetch("fiscal_year")).update!(submitted_on: h.fetch("submitted_on"))
      end
      OfficerTerm.find_each { it.send(:schedule_registration) if it.representative? && it.registrations.none? }
    end
    puts "人 #{Person.count}、会員 #{Membership.count}、役員の任期 #{OfficerTerm.count}、事業報告書 #{AnnualReport.count}"
  end
end
