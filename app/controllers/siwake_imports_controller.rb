class SiwakeImportsController < ApplicationController
  def index
    @imports = SiwakeImport.order(:filename)
  end

  def show
    @import = SiwakeImport.find(params[:id])
  end

  def new
  end

  def create
    files = Array(params[:files]).compact_blank
    return redirect_to(new_siwake_import_path, alert: "ファイルを選んでください") if files.empty?

    messages = files.map do |file|
      result = Kaikeiou::SiwakeImporter.new(file.read, filename: file.original_filename).import
      result.created ? "#{file.original_filename}: #{result.siwake_import.entries_count} 件を取り込みました" : "#{file.original_filename}: #{result.skipped_reason}"
    rescue Kaikeiou::SiwakeFile::FormatError, KeyError => e
      "#{file.original_filename}: 読み込めません（#{e.message}）"
    end
    redirect_to siwake_imports_path, notice: messages.join(" / ")
  end

  def destroy
    import = SiwakeImport.find(params[:id])
    import.destroy!
    redirect_to siwake_imports_path, notice: "#{import.filename} の取り込みを取り消しました"
  end
end
