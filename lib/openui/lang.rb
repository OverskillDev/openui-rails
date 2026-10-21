# frozen_string_literal: true

# OpenUI Lang (openui.com/docs/openui-lang) in Ruby: the language of
# thesysdev/openui, specification 1.0 (2026-10-12). No Rails or RubyLLM
# constants are referenced from this tree.
require_relative "version"
require_relative "lang/tokens"
require_relative "lang/lexer"
require_relative "lang/ast"
require_relative "lang/statements"
require_relative "lang/expressions"
require_relative "lang/limits"
require_relative "lang/errors"
require_relative "lang/values"
require_relative "lang/builtins"
require_relative "lang/validation"
require_relative "lang/schema"
require_relative "lang/materialize"
require_relative "lang/parser"
require_relative "lang/stream_parser"
require_relative "lang/message"
require_relative "lang/merge"
require_relative "lang/form_validation"

module OpenUI
  module Lang
    SPEC_VERSION = "1.0"

    module_function

    # Parse a complete program against a library.
    # @param library [OpenUI::Library, Schema]
    def parse(text, library:, limits: Limits.default, placeholders: false)
      parser_for(library, limits: limits, placeholders: placeholders).parse(text)
    end

    def parser_for(library, limits: Limits.default, placeholders: false)
      if library.is_a?(Schema)
        Parser.new(library, limits: limits, placeholders: placeholders)
      else
        Parser.new(library.schema, root: library.root, functions: library.function_implementations,
          limits: limits, placeholders: placeholders)
      end
    end

    def stream_parser_for(library, limits: Limits.default, placeholders: false)
      if library.is_a?(Schema)
        StreamParser.new(library, limits: limits, placeholders: placeholders)
      else
        StreamParser.new(library.schema, root: library.root, functions: library.function_implementations,
          limits: limits, placeholders: placeholders)
      end
    end
  end
end
