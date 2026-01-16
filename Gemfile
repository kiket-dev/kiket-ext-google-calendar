# frozen_string_literal: true

source "https://rubygems.org"

ruby "~> 3.4"

# Kiket SDK - from GitHub package repository
gem "kiket-sdk", git: "https://github.com/kiket-dev/kiket-ruby-sdk.git", branch: "main"

# Web framework (included by SDK, but listed for clarity)
gem "sinatra", "~> 4.0"
gem "puma", "~> 6.4"

# JSON handling
gem "json", "~> 2.7"

# HTTP client
gem "net-http", "~> 0.4"

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "rack-test", "~> 2.1"
  gem "webmock", "~> 3.23"
  gem "rubocop", "~> 1.60"
  gem "rubocop-rspec", "~> 2.26"
  gem "dotenv", "~> 3.1"
end
