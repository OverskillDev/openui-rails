# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

task default: :test

namespace :catalog do
  desc "Regenerate CATALOG.md from lib/openui/rails/catalog.rb"
  task :md do
    require "rails"
    require_relative "lib/openui-rails"
    File.write(File.expand_path("CATALOG.md", __dir__), "#{OpenUI::Rails::Catalog.markdown}\n")
    puts "wrote CATALOG.md"
  end
end
