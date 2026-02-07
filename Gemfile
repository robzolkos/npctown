source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"

# Authentication
gem "bcrypt", "~> 3.1.7"

# IDs - Stripe-style prefixed KSUIDs
gem "ksuid"

# Frontend - Inertia + Vite
gem "inertia_rails", "~> 3.0"
gem "vite_rails"

# Background Jobs
gem "sidekiq", "~> 8.0"
gem "sidekiq-scheduler"
gem "redis", "~> 5.0"

# Platform support
gem "tzinfo-data", platforms: %i[windows jruby]
gem "bootsnap", require: false
gem "thruster", require: false

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "dotenv-rails"
end

group :development do
  gem "web-console"
end

group :test do
  gem "mocha"
end
