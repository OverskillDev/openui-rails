# frozen_string_literal: true

module OpenUI
  module Lang
    # A rendered component instance: the tree node renderers consume.
    Element = Struct.new(:type, :props, :statement_id, :partial, keyword_init: true) do
      def prop(key)
        props[key.to_s]
      end

      def to_h
        {"type" => type, "props" => props, "statementId" => statement_id, "partial" => partial}.compact
      end
    end

    # A value produced by evaluating an expression, state read, query result
    # or call. Validation leaves these alone (language.md 8.2: scalar checks
    # apply to literals; the runtime owns expressions). Unwrapped before use.
    Dynamic = Struct.new(:value)

    # A `$variable` passed to a bindable prop (language.md 5.2).
    Binding = Struct.new(:name) do
      def to_h
        {"$binding" => name}
      end
    end

    # An unresolved reference kept in place for skeleton rendering. Only
    # produced when a parser runs with placeholders: true; language.md 4 rule 5
    # ("no placeholders") is the default.
    Placeholder = Struct.new(:name) do
      def to_s
        ""
      end
    end

    # One action step (language.md 6.3). +type+ is one of :continue_conversation,
    # :open_url, :set, :reset, :run, :custom_action.
    Step = Struct.new(:type, :data, keyword_init: true)

    # An ordered list of steps a component triggers through its action prop.
    # openui-rails v0.1 never runs these; the host's interaction hook receives them.
    ActionPlan = Struct.new(:steps) do
      def empty?
        steps.empty?
      end
    end

    module Values
      module_function

      # Strip Dynamic wrappers deeply.
      def unwrap(value)
        case value
        when Dynamic then unwrap(value.value)
        when Array then value.map { |v| unwrap(v) }
        when Hash then value.transform_values { |v| unwrap(v) }
        when ActionPlan then value
        else value
        end
      end

      def element?(value)
        value.is_a?(Element)
      end
    end
  end
end
