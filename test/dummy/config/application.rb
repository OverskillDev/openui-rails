# frozen_string_literal: true

require_relative "boot"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "turbo-rails"
require "propshaft"
require "ruby_llm"
require "openui-rails"

module Dummy
  class Application < Rails::Application
    config.load_defaults [Rails::VERSION::MAJOR, Rails::VERSION::MINOR].join(".").to_f
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = "openui-rails-dummy-secret-key-base-not-for-production"
    config.hosts.clear
    config.consider_all_requests_local = true
    config.action_dispatch.show_exceptions = :none if config.action_dispatch.respond_to?(:show_exceptions)
    config.active_support.deprecation = :stderr
    config.log_level = :warn
    config.logger = ActiveSupport::Logger.new(File.join(config.root, "log", "#{Rails.env}.log"))
  end
end
