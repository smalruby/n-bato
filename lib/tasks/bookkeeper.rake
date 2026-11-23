# API キーを使わず、手元の Claude Code が経理担当として仕訳を提案するための入口。
#   1. bin/rails 'bookkeeper:prompt[ID]'  … 証憑 ID の指示文・科目表・過去の仕訳と、添付ファイルの場所を出す
#   2. Claude Code がファイルを読み、SCHEMA の形の JSON を作る
#   3. bin/rails 'bookkeeper:import[ID,path/to/answer.json]' … 提案として登録(承認は画面で人が行う)
namespace :bookkeeper do
  desc "証憑の仕訳提案に使う指示文と添付ファイルの場所を表示する"
  task :prompt, [ :voucher_id ] => :environment do |_, args|
    voucher = Voucher.find(args.fetch(:voucher_id))
    gen = Bookkeeper::ProposalGenerator.new(voucher)
    puts gen.system_prompt
    puts "\n## 証憑 ##{voucher.id}"
    puts gen.content_blocks.last[:text]
    voucher.files.each do |file|
      path = ActiveStorage::Blob.service.path_for(file.key)
      puts "添付: #{path} (#{file.content_type}, #{file.filename})"
    end
    puts "\n## 答えの形(JSON Schema)"
    puts JSON.pretty_generate(Bookkeeper::ProposalGenerator::SCHEMA)
  end

  desc "Claude Code が作った答え(JSON)を、証憑の仕訳提案として登録する"
  task :import, [ :voucher_id, :path ] => :environment do |_, args|
    voucher = Voucher.find(args.fetch(:voucher_id))
    result = JSON.parse(File.read(args.fetch(:path)))
    proposals = Bookkeeper::ProposalGenerator.new(voucher).apply(result, model: "claude-code")
    voucher.reload
    if voucher.status == "error"
      abort "登録できませんでした: #{voucher.ai_error}"
    else
      puts "#{proposals.size} 件の提案を登録しました。画面で確認・承認してください。"
      puts "確認事項: #{voucher.ai_questions}" if voucher.ai_questions.present?
    end
  end
end
