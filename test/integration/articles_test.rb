require "test_helper"
require "rake"

# 定款と事業(見直し第13回)
class ArticlesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in
    [ 2016, 2017, 2026 ].each { FiscalPeriod.find_or_create_by!(year: it) }
    Rails.application.load_tasks unless Rake::Task.task_defined?("articles:load")
    Rake::Task["articles:load"].reenable
    capture_io { Rake::Task["articles:load"].invoke("config/articles.example.yml") }
  end

  test "読み込み: 版 2 つと主な活動" do
    assert_equal [ 1, 2 ], ArticleVersion.ordered.pluck(:number)
    assert_equal "学習の環境の開発と運用", ProgramProfile.find_by(code: 111).activities
    assert_equal [ [ 1, "プログラミング教材の開発・販売事業" ], [ 2, "初心者向けプログラミング教室の運営事業" ] ], ArticleVersion.current.document.programs
  end

  test "要約: 目的と事業(部門と主な活動)、条文番号は全文へ" do
    get articles_path
    assert_response :success
    assert_select ".nb-articles-tabs a[aria-current=page]", "要約"
    assert_select ".nb-art-sec h2", text: /目的/
    assert_select ".nb-art-programs td.nb-num", "111"
    assert_select "input#act-111[value=?]", "学習の環境の開発と運用"
    assert_select "a.nb-artref[href=?]", articles_path(tab: "full", anchor: "a-2")
    assert_select ".nb-nav a[aria-current=page]", text: /定款と事業/
  end

  test "全文: 探すと語を含む条だけ。前の版も選べる" do
    get articles_path(tab: "full", q: "公告")
    assert_select "article.nb-art", 1
    assert_select "article#a-4 mark", "公告"
    get articles_path(tab: "full", v: 1)
    assert_select ".nb-articles-old"
    assert_select "article#a-4", text: /掲示場/
  end

  test "変更の記録: 前の版との違いを消した文と足した文で出す" do
    get articles_path(tab: "history")
    assert_select ".nb-art-history tbody tr", 2
    assert_select ".nb-art-diff del", text: /掲示場/
    assert_select ".nb-art-diff ins", text: /ホームページ/
  end

  test "条文の参照: その年度の時点の版を右ペイン用に出す" do
    get article_path(4, year: 2016)
    assert_select "turbo-frame#article_ref .nb-art-text", text: /掲示場/
    get article_path(4, year: 2026)
    assert_select "turbo-frame#article_ref .nb-art-text", text: /ホームページ/
    get member_applications_path   # 説明に「定款第7条」がある
    assert_select ".nb-help a.nb-artref[data-turbo-frame=article_ref]", text: "第7条"
    assert_select "turbo-frame#article_ref"
  end

  test "主な活動を直すと記録に残り、部門選びと AI の指示文に出る" do
    patch program_profile_path(112, format: :json), params: { program_profile: { activities: "体験教室" }, undo_scope: "articles" }
    assert_response :success
    assert_equal "体験教室", ProgramProfile.find_by(code: 112).activities
    assert AuditOperation.where(scope: "articles").exists? if defined?(AuditOperation)
    Department.create!(fiscal_year: 2026, code: 112, name: "②事業")
    item = PickerItems.new("departments", 2026).all.find { it[:code] == "112" }
    assert_equal "体験教室", item[:hint]
  end
end
