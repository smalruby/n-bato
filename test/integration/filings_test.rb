require "test_helper"

# 所轄庁へ出す書類を 1 つずつ PDF で出す(一式は annual_report_flow_test)。データは架空
class FilingsTest < ActionDispatch::IntegrationTest
  setup do
    import_sample
    ensure_organization
    AnnualReport.create!(fiscal_year: 2024)
    sign_in
  end

  test "書類を 1 つだけ PDF にすると、ファイルの名前は年度と書類の名前" do
    assert_pdf document_annual_report_path(2024, "balance_sheet", format: :pdf)
    assert_match "2024-balance_sheet.pdf", response.headers["Content-Disposition"]
    assert_match "貸借対照表", PdfRenderer::Fake.last_html
  end
end
