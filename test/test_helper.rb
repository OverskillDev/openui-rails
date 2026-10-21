# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
Encoding.default_external = Encoding::UTF_8
require "minitest/autorun"
require "json"
require "openui/lang"

module OpenUI
  module TestSupport
    FIXTURES = File.expand_path("fixtures", __dir__)
    GOLDEN = File.join(FIXTURES, "golden")
    OPENUI_FIXTURES = File.join(FIXTURES, "openui", "1.0")

    module_function

    def fixture_spec
      @fixture_spec ||= JSON.parse(File.read(File.join(OPENUI_FIXTURES, "library.json")))
    end

    # The conformance test library as a compiled Schema (no Library DSL involved).
    def fixture_schema
      spec = fixture_spec
      bindable = spec["components"].to_h { |n, c| [n, c["signature"].scan(/(\w+)\??: \$binding</).flatten] }
      OpenUI::Lang::Schema.new(spec["schema"], root: spec["root"], bindable: bindable)
    end

    def fixture_functions
      {"Upper" => ->(text:) { text.to_s.upcase }}
    end

    def fixture_parser(limits: OpenUI::Lang::Limits.default)
      OpenUI::Lang::Parser.new(fixture_schema, root: "Stack", functions: fixture_functions, limits: limits)
    end

    def fixture_stream_parser(limits: OpenUI::Lang::Limits.default)
      OpenUI::Lang::StreamParser.new(fixture_schema, root: "Stack", functions: fixture_functions, limits: limits)
    end
  end
end
