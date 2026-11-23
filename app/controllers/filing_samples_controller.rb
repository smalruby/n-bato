# 様式の例をまとめてダウンロード(見直し第17回)。Nばとが作る提出書類を、架空の法人・空の帳簿で 1 つの PDF にする。
# 自治体の様式と違っていたら、連絡先(NBATO_SUPPORT_URL)に知らせてもらう。
class FilingSamplesController < ApplicationController
  layout "print"
  SAMPLE_YEAR = 1999 # 実データの無い年度(会員・役員・仕訳が入らない)

  def self.support_url = ENV["NBATO_SUPPORT_URL"].presence

  def show
    @docs = FilingsController::DOCUMENTS.keys
    @title = "様式の例(事業報告書等一式)"
    @fiscal_year = FiscalYear.new(SAMPLE_YEAR)
    @annual_report = AnnualReport.new(fiscal_year: SAMPLE_YEAR, achievements: "（例）この欄に、その年度の事業の成果を書きます。")
    @statement = Ledger::YearStatement.new(@fiscal_year, {}, [])
    @report = Ledger::Report.new(@statement)
    @organization = Organization.new(name: "（例）NPO法人サンプル", address: "（例）○○県○○市○○町１－２－３", representative_title: "理事長",
                                     representative_name: "（例）○○　○○", phone: "000-0000-0000", first_fiscal_year: SAMPLE_YEAR)
    @addressee = "（例）○○市長　○○　○○"
    respond_to do |format|
      format.html { render "filings/documents" }
      # :nocov:
      format.pdf do
        @pdf = true
        send_data PdfRenderer.render(render_to_string("filings/documents", formats: [ :html ])),
                  filename: "n-bato-forms-sample.pdf", type: "application/pdf", disposition: "attachment"
      end
      # :nocov:
    end
  end
end
