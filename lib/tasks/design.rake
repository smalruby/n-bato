namespace :design do
  desc "docs/design-system の tokens.json と components.css から app/assets/tailwind/nbato.css を作る"
  task :tokens do
    root = Pathname(__dir__).join("../..")
    t = JSON.parse(root.join("docs/design-system/tokens.json").read)
    vars = ->(theme) { t["color"]["tokens"].map { "  --#{it['name']}: #{it['value'][theme]};" } }
    flat = %w[spacing radius size].flat_map { |k| t[k]["tokens"].map { "  --#{it['name']}: #{it['value']};" } }
    fonts = t["type"]["families"].map { |k, v| "  --font-#{k}: #{v};" }
    shadow = ->(theme) { t["shadow"]["tokens"].map { "  --#{it['name']}: #{it['value'][theme]};" } }
    css = +"/* 自動生成(bin/rails design:tokens)。直接直さない。原本は docs/design-system/。 */\n"
    css << ":root {\n#{(vars.('light') + flat + fonts + shadow.('light')).join("\n")}\n}\n"
    css << "/* ダークは画面の移行が済むまで data-theme=\"dark\" のときだけ */\n"
    css << ":root[data-theme=\"dark\"] {\n#{(vars.('dark') + shadow.('dark')).join("\n")}\n}\n\n"
    css << root.join("docs/design-system/components.css").read
    root.join("app/assets/tailwind/nbato.css").write(css)
    puts "app/assets/tailwind/nbato.css"
  end
end
