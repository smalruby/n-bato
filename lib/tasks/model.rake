namespace :model do
  desc "長いイベントのいまの状態を、詳細のイベントから作り直して照合する(docs/adr/0005)"
  task verify: :environment do
    list = ModelVerification.mismatches
    if list.empty?
      puts "model:verify: いまの状態は、イベントから作り直した状態と一致しています"
    else
      list.each { warn it }
      abort "model:verify: #{list.size} 件が食い違っています"
    end
  end
end
