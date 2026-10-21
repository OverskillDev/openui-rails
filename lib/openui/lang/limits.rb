# frozen_string_literal: true

module OpenUI
  module Lang
    # Host safety caps. Model output is untrusted; these bound the work the
    # parser and renderer do for one response. Exceeding a cap stops parsing
    # and records a `limit-exceeded` error (an openui-rails extension, source
    # "host"); nothing raises.
    Limits = Struct.new(
      :max_input_bytes,     # whole response text
      :max_pending_bytes,   # the streaming tail re-parsed on every chunk
      :max_statements,
      :max_depth,           # nested brackets
      :max_string_length,   # one string literal
      :max_elements,        # rendered component instances
      :max_each_items,      # @Each iterations
      keyword_init: true
    ) do
      def self.default
        new(
          max_input_bytes: 262_144,
          max_pending_bytes: 65_536,
          max_statements: 2_000,
          max_depth: 64,
          max_string_length: 32_768,
          max_elements: 10_000,
          max_each_items: 1_000
        )
      end

      def merge(overrides)
        dup.tap { |l| overrides.each { |k, v| l[k] = v } }
      end
    end
  end
end
