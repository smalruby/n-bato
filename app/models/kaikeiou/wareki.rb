module Kaikeiou
  # 会計王の和暦日付("H.36/04/15")。会計王は令和以降も平成のまま数える。
  module Wareki
    ERAS = {"M" => 1867, "T" => 1911, "S" => 1925, "H" => 1988, "R" => 2018}.freeze
    PATTERN = %r{\A([MTSHR])\.(\d{1,3})/(\d{2})/(\d{2})\z}

    module_function

    def parse(text)
      m = PATTERN.match(text.to_s) or raise ArgumentError, "和暦の日付として読めません: #{text.inspect}"
      Date.new(ERAS.fetch(m[1]) + m[2].to_i, m[3].to_i, m[4].to_i)
    end

    # 会計王と同じく、平成 1 年(1989 年)以降は "H." で書く。
    def format(date)
      era, offset = (date.year >= 1989) ? ["H", ERAS["H"]] : ERAS.select { |_, base| date.year > base }.max_by(&:last)
      Kernel.format("%s.%02d/%02d/%02d", era, date.year - offset, date.month, date.day)
    end
  end
end
