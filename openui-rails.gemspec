# frozen_string_literal: true

require_relative "lib/openui/version"

Gem::Specification.new do |spec|
  spec.name = "openui-rails"
  spec.version = OpenUI::VERSION
  spec.authors = ["Todd Dickerson"]
  spec.email = ["todd@clickfunnels.com"]

  spec.summary = "OpenUI Lang for Rails: a streaming parser, a component library DSL, " \
                 "server-rendered ERB components, Turbo Stream progressive rendering, and a RubyLLM hook."
  spec.description = "Render model-generated UI in Rails from OpenUI Lang (openui.com), the line-oriented " \
                     "generative UI language. Ships a spec-faithful parser, a library DSL that generates the " \
                     "system prompt, ERB rendering with Hotwire progressive updates, and chat.with_openui for RubyLLM."
  spec.homepage = "https://github.com/OverskillDev/openui-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "app/**/*", "config/**/*", "LICENSE", "NOTICE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  # Core (lib/openui/lang, lib/openui/library) has no runtime dependencies.
  # The Rails engine and the RubyLLM hook load only when their gems are present.
  spec.add_dependency "railties", ">= 7.1"
  spec.add_dependency "actionview", ">= 7.1"
end
