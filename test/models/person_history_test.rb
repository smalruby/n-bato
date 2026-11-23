require "test_helper"

# 住所の変更・改姓を日付つきの出来事で持つ(見直し第20回、docs/adr/0029)。値はすべて架空。
class PersonHistoryTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @p = Person.create!(name: "田中　花子", name_kana: "たなか はなこ", address: "テスト県テスト市1-1")
    @director = Person.create!(name: "山田　一郎", address: "テスト県テスト市9-9")
  end

  test "住所が変わった: いまの値・その日の値・記録の始まり" do
    Person::AddressChange.record!(@p, address: "テスト県テスト市2-2", moved_on: Date.new(2025, 4, 1), date_precision: "month", by: @user)
    Person::AddressChange.record!(@p, address: "テスト県テスト市3-3", moved_on: Date.new(2025, 10, 5), by: @user)
    @p.reload
    assert_equal "テスト県テスト市3-3", @p.address
    assert_equal "テスト県テスト市1-1", @p.address_at_start
    assert_equal "テスト県テスト市1-1", @p.address_on(Date.new(2025, 3, 31))
    assert_equal "テスト県テスト市2-2", @p.address_on(Date.new(2025, 10, 4))
    assert @p.changes_recorded?
    assert_equal [ :start, :address, :address ], @p.history.map(&:kind)
    assert_equal "2025/04(日は不明)", @p.address_changes.first.date_label
    assert_equal "2025/10/05", @p.address_changes.last.date_label
  end

  test "同じ住所・空の住所は記録しない" do
    assert_raises(ArgumentError) { Person::AddressChange.record!(@p, address: "テスト県テスト市1-1", moved_on: Date.current) }
    assert_raises(ArgumentError) { Person::AddressChange.record!(@p, address: " ", moved_on: Date.current) }
  end

  test "氏名が変わった: 旧氏の併記と「氏変更」" do
    c = Person::NameChange.record!(@p, name: "鈴木　花子", changed_on: Date.new(2025, 9, 8), show_former_name: "1", by: @user)
    @p.reload
    assert_equal "鈴木　花子", @p.name
    assert_equal "たなか はなこ", @p.name_kana, "よみを入れなければ前のまま"
    assert_equal "田中　花子", c.former_name
    assert_equal "氏変更", c.change_word
    assert_equal "鈴木　花子（田中　花子）", c.name_with_former
    assert_equal "鈴木　花子（田中　花子）", @p.display_name_on(Date.new(2026, 3, 31))
    assert_equal "田中　花子", @p.display_name_on(Date.new(2025, 9, 7))
    assert_equal "田中　花子", @p.name_on(Date.new(2025, 9, 7))
    assert_equal "たなか はなこ", @p.name_kana_on(Date.new(2025, 9, 7))
    assert_equal @p, Person.find_by_current_name("鈴木 花子")
    assert_nil Person.find_by_current_name(" ")
    assert_equal [ :start, :name ], @p.history.map(&:kind)
    assert_equal "鈴木　花子（田中　花子）", @p.history.last.name
  end

  test "名変更・氏名変更・区切れない氏名" do
    p2 = Person.create!(name: "田中　花子")
    assert_equal "名変更", Person::NameChange.record!(p2, name: "田中　花", changed_on: Date.current).change_word
    assert_equal "氏名変更", Person::NameChange.record!(p2, name: "鈴木　一", changed_on: Date.current).change_word
    c = Person::NameChange.record!(p2, name: "鈴木一", changed_on: Date.current)
    assert_equal "氏名変更", c.change_word
    assert_equal "鈴木一（鈴木　一）", c.name_with_former
    assert_equal "鈴木一", c.display_name
    assert_raises(ArgumentError) { Person::NameChange.record!(p2, name: "鈴木一", changed_on: Date.current) }
    assert_raises(ArgumentError) { Person::NameChange.record!(p2, name: "", changed_on: Date.current) }
  end

  test "日付の入れ方: 日が無ければ月まで。無い日付・空の年月は受け付けない" do
    assert_equal [ Date.new(2025, 4, 1), "month" ], Person::AddressChange.parse_date(year: "2025", month: "4", day: "")
    assert_equal [ Date.new(2025, 4, 3), "day" ], Person::AddressChange.parse_date(year: 2025, month: 4, day: 3)
    assert_raises(ArgumentError) { Person::AddressChange.parse_date(year: "2025", month: "2", day: "30") }
    assert_raises(ArgumentError) { Person::AddressChange.parse_date(year: "", month: "4") }
    c = Person::AddressChange.record!(@p, address: "テスト県テスト市5-5", moved_on: Date.new(2024, 4, 1), date_precision: "fiscal_year")
    assert_equal "2024年度のうち(日は不明)", c.date_label
    assert_not c.day_known?
  end

  test "取り消せるのはいちばん新しい出来事だけ。取り消すと前の値に戻る" do
    a = Person::AddressChange.record!(@p, address: "テスト県テスト市2-2", moved_on: Date.new(2025, 4, 1))
    b = Person::AddressChange.record!(@p, address: "テスト県テスト市3-3", moved_on: Date.new(2025, 5, 1))
    assert_raises(ArgumentError) { Person::ChangeCancellation.cancel!(a, by: @user, reason: "打ち間違い") }
    assert_raises(ArgumentError) { Person::ChangeCancellation.cancel!(b, by: @user, reason: " ") }
    Person::ChangeCancellation.cancel!(b, by: @user, reason: "打ち間違い")
    @p.reload
    assert_equal "テスト県テスト市2-2", @p.address
    assert b.reload.cancelled?
    assert_raises(ArgumentError) { Person::ChangeCancellation.cancel!(b, by: @user, reason: "もう一度") }
    assert @p.history.last.change.cancelled?
    assert_equal "テスト県テスト市2-2", @p.history.last.address, "取り消した出来事は値を変えない"
  end

  test "代表権のある理事の住所・氏名が変わると登記の事由ができる(日が不明なら期限も不明)" do
    OfficerTerm.create!(person: @p, role: "vice_chair", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
    OfficerTerm.create!(person: @director, role: "director", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
    a = Person::AddressChange.record!(@p, address: "テスト県テスト市2-2", moved_on: Date.new(2025, 4, 1), date_precision: "month")
    n = Person::NameChange.record!(@p, name: "鈴木　花子", changed_on: Date.new(2025, 9, 8))
    Person::AddressChange.record!(@director, address: "テスト県テスト市8-8", moved_on: Date.new(2025, 4, 1))
    assert_equal "address_change", a.registration.kind
    assert_nil a.registration.due_on
    assert_equal Date.new(2025, 9, 22), n.registration.due_on
    assert_equal 0, Registration.where(kind: "address_change").count - 1, "代表権のない理事は登記しない"
    Person::ChangeCancellation.cancel!(n, by: @user, reason: "打ち間違い")
    assert_nil Registration.find_by(person_name_change_id: n.id), "取り消すと登記の事由も消える"
  end

  test "登記の申請に入れた出来事は取り消せない" do
    OfficerTerm.create!(person: @p, role: "chair", starts_on: Date.new(2024, 7, 1), ends_on: Date.new(2026, 6, 30))
    a = Person::AddressChange.record!(@p, address: "テスト県テスト市2-2", moved_on: Date.new(2025, 4, 3))
    RegistrationFiling.start!([ a.registration ])
    assert_raises(ArgumentError) { Person::ChangeCancellation.cancel!(a, by: @user, reason: "打ち間違い") }
  end
end
