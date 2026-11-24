# やることの一覧(デザインシステム TodoList)。出どころは 3 種類: 依頼(Todo)・義務(Compliance::Checklist)・手続き(進めている手続きの次の手順)。
# 年度をまたいで 1 つの一覧にする(操作している年度では絞らない)。
class TodoList
  Group = Data.define(:key, :source, :title, :note, :due_on, :request, :items)
  Item = Data.define(:status, :fiscal_year, :title, :kind_label, :assignee, :due_on, :path, :todo, :note) do
    def done? = status == "done"
    def overdue?(today = Date.current) = !done? && due_on.present? && due_on < today
  end
  SOURCES = { "request" => "依頼", "duty" => "義務", "procedure" => "手続き", "application" => "入会申込" }.freeze
  # 件数のまとめ(デザインシステム TodoSummary、見直し第12回)の札。期限ごとと担当ごと。
  DUES = { "over" => "期限を過ぎた", "week" => "7 日以内", "later" => "それより先", "none" => "期限なし" }.freeze
  WHOS = { "human" => "人がやる", "ai" => "AI がやる" }.freeze
  SOON_DAYS = 7

  def initialize(helpers:, today: Date.current, source: nil, year: nil, include_done: false, due: nil, who: nil)
    @h, @today, @source, @year, @include_done = helpers, today, source.presence, year.presence&.to_i, include_done
    @due, @who = due.presence_in(DUES.keys), who.presence_in(WHOS.keys)
  end

  def groups
    @groups ||= raw_groups.map { filter(it) }.reject { it.items.empty? }
  end

  # 済んでいないやることを、期限ごと・担当ごとに数える(出どころ・年度の絞り込みの中で。札の絞り込みは数に入れない)。
  def summary
    @summary ||= begin
      open = raw_groups.flat_map { narrow(it.items) }.reject(&:done?)
      counts = (DUES.keys + WHOS.keys).index_with(0)
      open.each { counts[due_key(it)] += 1; counts[who_key(it)] += 1 }
      counts
    end
  end

  def due_key(item)
    return "none" unless item.due_on
    return "over" if item.due_on < @today

    item.due_on <= @today + SOON_DAYS ? "week" : "later"
  end

  def who_key(item) = item.assignee.to_s.strip == "AI" ? "ai" : "human"

  def items = groups.flat_map(&:items)

  # ホーム用: 期限を過ぎたものと、30 日以内のもの
  def near(days: 30) = items.reject(&:done?).select { it.due_on && it.due_on <= @today + days }.sort_by(&:due_on)

  private

  def raw_groups
    @raw_groups ||= begin
      list = []
      list.concat(request_groups) if @source.nil? || @source == "request"
      list << duty_group if @source.nil? || @source == "duty"
      list << procedure_group if @source.nil? || @source == "procedure"
      list << application_group if @source.nil? || @source == "application"
      list.compact
    end
  end

  def narrow(items)
    @year ? items.select { it.fiscal_year == @year } : items
  end

  def filter(group)
    items = narrow(group.items)
    items = items.reject(&:done?) unless @include_done
    items = items.select { !it.done? && due_key(it) == @due } if @due
    items = items.select { !it.done? && who_key(it) == @who } if @who
    group.with(items:)
  end

  def request_groups
    Todo.refresh_auto!
    IncomingRequest.ordered.includes(:todos).map do |r|
      next if r.resolved? && !@include_done

      items = r.todos.map do |t|
        Item.new(status: t.status, fiscal_year: t.fiscal_year, title: t.title, kind_label: t.kind_label, assignee: t.assignee,
                 due_on: t.due_on, path: @h.todo_path(t), todo: t,
                 note: [ (t.status == "wait" && t.waiting_on.present? ? "待ち: #{t.waiting_on}" : nil), (t.done? ? t.done_note.presence : nil) ].compact.join(" "))
      end
      Group.new(key: "request-#{r.id}", source: "request", title: r.title, note: [ r.counterpart.presence, ("#{r.done_count} / #{r.todos.size} 済み" if r.todos.any?) ].compact.join("・"),
                due_on: r.due_on, request: r, items:)
    end.compact
  end

  def duty_group
    items = Compliance::Checklist.new(today: @today).items.map do |c|
      st = c.done? ? "done" : "todo"
      Item.new(status: st, fiscal_year: c.title[/(\d{4})年度/, 1]&.to_i, title: c.title, kind_label: c.category, assignee: "理事長",
               due_on: c.due_on, path: c.path, todo: nil, note: c.note.to_s)
    end
    Group.new(key: "duty", source: "duty", title: "定款・法律の義務", note: "n-bato が期限から自動で出す", due_on: nil, request: nil, items:)
  end

  # 届いて、まだ認めていない入会申込。期限は付けない(Slack のリマインドに名前を流さないため)。
  def application_group
    items = MemberApplication.received.order(:applied_on).map do |a|
      Item.new(status: "todo", fiscal_year: a.default_year, title: "入会申込が届いた: #{a.name}", kind_label: "画面", assignee: "理事長",
               due_on: nil, path: @h.member_application_path(a), todo: nil, note: "#{a.applied_on.strftime('%Y/%m/%d')} に申込")
    end
    Group.new(key: "application", source: "application", title: "入会申込", note: "認めるかを決める(定款第7条)", due_on: nil, request: nil, items:)
  end

  def procedure_group
    items = ProcedureRun.ordered.reject(&:finished?).filter_map do |run|
      next unless (step = run.next_step)

      Item.new(status: step.status == "current" ? "doing" : "todo", fiscal_year: run.period.to_i.positive? ? run.period.to_i : nil,
               title: "#{run.name}: #{step.definition.title}", kind_label: "手続き", assignee: "理事長", due_on: run.due_on,
               path: @h.procedure_path(run, step: step.key), todo: nil, note: run.period_label)
    end
    Group.new(key: "procedure", source: "procedure", title: "進めている手続き", note: "次の手順", due_on: nil, request: nil, items:)
  end
end
