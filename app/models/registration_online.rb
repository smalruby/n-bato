# 登記・供託オンライン申請システムの使える時間と、いま使えるか(見直し第20回)。設定は config/registration_online.yml。
# Nばとは祝日の暦を持たないので、土日だけを休日として数え、平日には「祝日なら …」と添える。
module RegistrationOnline
  module_function

  Status = Struct.new(:open, :message, :office_message)
  WDAYS = %w[日 月 火 水 木 金 土].freeze

  def config = @config ||= Rails.application.config_for(:registration_online).with_indifferent_access
  def url = config[:url]
  def condition_url = config[:condition_url]

  def hours_label
    w = config[:weekday]
    h = config[:holiday]
    c = config[:closed].map { it.tr("-", "/").sub(%r{\A0}, "").sub(%r{/0}, "/") }
    "平日 #{w[0]}〜#{w[1]} / 休日・祝日 #{h[0]}〜#{h[1]}(#{c[0]}〜#{c[1]} は使えない)"
  end

  def office_label = "法務局の受付は平日 #{config[:office][0]}〜#{config[:office][1]}"

  def closed_day?(date)
    from, to = config[:closed].map { Date.strptime("#{date.year}-#{it}", "%Y-%m-%d") }
    (from > to) ? (date >= from || date <= to) : date.between?(from, to)
  end

  def holiday?(date) = date.saturday? || date.sunday?

  def hours_on(date)
    return nil if closed_day?(date)

    holiday?(date) ? config[:holiday] : config[:weekday]
  end

  def at(date, hhmm) = Time.zone.parse("#{date} #{hhmm}")

  # 次に使える日の始まり(now より後)
  def next_open_after(now)
    date = now.to_date
    loop do
      h = hours_on(date)
      return at(date, h[0]) if h && at(date, h[0]) > now

      date += 1
    end
  end

  def status(now = Time.current)
    date = now.to_date
    h = hours_on(date)
    if h && now >= at(date, h[0]) && now < at(date, h[1])
      tail = holiday?(date) ? "" : "(祝日なら #{config[:holiday][1]} まで)"
      return Status.new(open: true, message: "いまは使えます。今日は #{h[1]} まで#{tail}", office_message: office_message(now))
    end

    nxt = next_open_after(now)
    day = {date => "今日", date + 1 => "明日"}.fetch(nxt.to_date) { "#{nxt.month}/#{nxt.day}(#{WDAYS[nxt.wday]})" }
    Status.new(open: false, message: "いまは使えません。次は#{day} #{nxt.strftime("%-H:%M")} から", office_message: office_message(now))
  end

  # いま送ったら、いつの受付になるか(期限の 2 週間に関わる)
  def office_message(now)
    date = now.to_date
    from, to = config[:office].map { at(date, it) }
    return "いま送ると、今日の受付になります(祝日なら次の平日)。" if !holiday?(date) && !closed_day?(date) && now >= from && now < to

    d = date + ((now < from && !holiday?(date) && !closed_day?(date)) ? 0 : 1)
    d += 1 while holiday?(d) || closed_day?(d)
    "いま送ると、#{d.month}/#{d.day}(#{WDAYS[d.wday]})の受付になります(祝日なら、その次の平日)。"
  end
end
