ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# カバレッジ(COVERAGE=1 bin/rails test)は、アプリを読み込む前に測り始める(test/simplecov_start.rb、docs/adr/0025)。
# 本番(RAILS_ENV=production)では、COVERAGE が紛れ込んでも測らない(遅くなり、100% の下限で終了コードが 0 でなくなるため)
require_relative "../test/simplecov_start" if ENV["COVERAGE"] && (ENV["RAILS_ENV"] || ENV["RACK_ENV"]) != "production"

require "bootsnap/setup" # Speed up boot time by caching expensive operations.
