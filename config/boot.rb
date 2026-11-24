ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# カバレッジ(COVERAGE=1 bin/rails test)は、アプリを読み込む前に測り始める(test/simplecov_start.rb、docs/adr/0025)
require_relative "../test/simplecov_start" if ENV["COVERAGE"]
