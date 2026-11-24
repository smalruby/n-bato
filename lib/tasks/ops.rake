namespace :ops do
  # bin/prod-runner が呼ぶ。スクリプトは base64 で OPS_SCRIPT に入れて渡す(引用符を気にしないため)。
  task run: :environment do
    require "base64"
    OpsScript.run!(source: Base64.decode64(ENV.fetch("OPS_SCRIPT")).force_encoding(Encoding::UTF_8),
                   name: ENV.fetch("OPS_SCRIPT_NAME"), apply: ENV["OPS_APPLY"] == "1")
  end
end
