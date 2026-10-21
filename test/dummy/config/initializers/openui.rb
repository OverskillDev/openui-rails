# frozen_string_literal: true

OpenUI::Rails.configure do |config|
  config.library = -> { OpenUI::Rails::StarterLibrary.build(id: "demo", version: "0.1.0") }
  config.placeholders = true
  config.catalog = true
end

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"] if ENV["OPENAI_API_KEY"]
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"] if ENV["OPENROUTER_API_KEY"]
end
