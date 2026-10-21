# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = false
  config.enable_reloading = true if config.respond_to?(:enable_reloading=)
end
