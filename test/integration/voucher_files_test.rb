require "test_helper"

# 証憑の添付は、ログインした人だけが開ける(#27)
class VoucherFilesTest < ActionDispatch::IntegrationTest
  setup do
    import_sample
    sign_in
    post vouchers_path, params: {voucher: {kind: "receipt", issued_on: "2025-06-01", description: "ケーブルを買った",
                                           files: [fixture_file_upload("receipt.png", "image/png")]}}
    @voucher = Voucher.last
    @file = @voucher.files.first
  end

  test "証憑の画面は、ログインを確かめる道筋で添付を出す" do
    get voucher_path(@voucher)
    assert_select "img[src=?]", voucher_file_path(@voucher, @file)
    assert_select "a[href=?]", voucher_file_path(@voucher, @file)
    assert_no_match "/rails/active_storage", response.body
  end

  test "ログインしていれば添付が開ける(画像はその場で出し、手元に残させない)" do
    get voucher_file_path(@voucher, @file)
    assert_response :success
    assert_equal file_fixture("receipt.png").binread.b, response.body.b
    assert_equal "image/png", response.media_type
    assert_match(/\Ainline/, response.headers["Content-Disposition"])
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "ログインしていなければ添付は開けない" do
    delete session_path
    get voucher_file_path(@voucher, @file)
    assert_redirected_to new_session_path
  end

  test "Active Storage の道筋は無い(署名付きの URL を知っていても開けない)" do
    assert_not Rails.application.routes.named_routes.key?(:rails_service_blob)
    delete session_path
    get "/rails/active_storage/blobs/redirect/#{@file.blob.signed_id}/receipt.png"
    assert_response :not_found
  end

  test "ほかの証憑の添付の番号では開けない" do
    other = Voucher.create!(kind: "receipt", issued_on: Date.new(2025, 6, 2), description: "別の証憑")
    get voucher_file_path(other, @file)
    assert_response :not_found
  end

  test "ブラウザで開くと危ない種類(HTML)は保存させる" do
    # 証憑の検証は画像と PDF しか受けないが、古いデータや検証の抜けに備え、添付を直に作って確かめる
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("<script>alert(1)</script>"), filename: "x.html", content_type: "text/html")
    html = ActiveStorage::Attachment.create!(record: @voucher, name: "files", blob:)
    get voucher_file_path(@voucher, html)
    assert_response :success
    assert_match(/\Aattachment/, response.headers["Content-Disposition"])
  end
end
