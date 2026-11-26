require "test_helper"

# Ruby は 4.0.10 以上だけ(それより前の版には危険な脆弱性がある。2026-11-26 理事長)。
# 下限は Gemfile の ruby で止める。ここでは、版を書いたところがそろっていて、下限を下回らないことを確かめる
class RubyVersionTest < ActiveSupport::TestCase
  FLOOR = Gem::Version.new("4.0.10")

  test "動いている Ruby が 4.0.10 以上" do
    assert_operator Gem::Version.new(RUBY_VERSION), :>=, FLOOR
  end

  test ".ruby-version と Dockerfile と Gemfile.lock の版がそろっていて、4.0.10 以上" do
    ruby_version = Rails.root.join(".ruby-version").read.strip
    dockerfile = Rails.root.join("Dockerfile").read[/^ARG RUBY_VERSION=(\S+)$/, 1]
    lock = Rails.root.join("Gemfile.lock").read[/^RUBY VERSION\n\s+ruby (\d+\.\d+\.\d+)/, 1]

    assert_operator Gem::Version.new(ruby_version), :>=, FLOOR
    assert_equal ruby_version, dockerfile, "Dockerfile の ARG RUBY_VERSION を .ruby-version に合わせてください"
    assert_equal ruby_version, lock, "bundle install で Gemfile.lock の RUBY VERSION を合わせてください"
  end

  test "Gemfile が 4.0.10 より前の Ruby を止める" do
    assert_match(/^ruby ">= 4\.0\.10"$/, Rails.root.join("Gemfile").read)
  end
end
