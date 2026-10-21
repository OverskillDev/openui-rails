# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.enable_reloading = false if config.respond_to?(:enable_reloading=)
  config.action_controller.allow_forgery_protection = false
end
