# frozen_string_literal: true

module OpenUI
  module Lang
    # The compiled form of a LibrarySpec JSON Schema (prompt.md section 2.3):
    # positional params per component, plus the call registry of built-ins,
    # library functions and actions. Mirrors compileSchema in the reference
    # parser.
    class Schema
      Param = Struct.new(:name, :required, :default, :schema, :bindable, keyword_init: true)
      Call = Struct.new(:kind, :params, :builtin, :lazy, :schema, keyword_init: true)

      attr_reader :components, :calls, :json, :root

      # @param json [Hash] the library JSON Schema ($defs, properties, functions, actions)
      # @param root [String, nil] the root component name
      # @param bindable [Hash{String => Array<String>}] bindable prop names per component
      def initialize(json, root: nil, bindable: {})
        @json = json
        @root = root
        @components = {}
        @calls = {}
        defs = json["$defs"] || {}
        names = json["properties"] ? json["properties"].keys : nil
        action_defs = {}
        (Builtins.action_defs.keys + (json["actions"] || {}).keys).each do |name|
          body = defs[name]
          action_defs["#/$defs/#{name}"] = body if body && !(names && names.include?(name))
        end
        defs.each do |name, d|
          skip = names ? !names.include?(name) : action_defs.key?("#/$defs/#{name}")
          next if skip
          @components[name] = compile_params(d, action_defs, bindable[name] || [])
        end
        Builtins::FUNCTIONS.each do |name, d|
          @calls[name] = Call.new(kind: :function, params: d[:params].map { |p| Param.new(name: p, required: false) },
            builtin: true, lazy: d[:lazy] || false)
        end
        Builtins::STEPS.each do |name, d|
          @calls[name] = Call.new(kind: :action, params: d[:params].map { |p| Param.new(name: p, required: false) },
            builtin: true, lazy: d[:lazy] || false)
        end
        @calls["Action"] = Call.new(kind: :action, params: [Param.new(name: "steps", required: true)], builtin: true, lazy: true)
        (json["functions"] || {}).each do |name, fn|
          @calls[name] = Call.new(kind: :function, params: compile_params(fn["params"] || {}, action_defs, []),
            builtin: false, lazy: false, schema: fn)
        end
        (json["actions"] || {}).each do |name, act|
          @calls[name] = Call.new(kind: :action, params: compile_params(act["params"] || {}, action_defs, []),
            builtin: false, lazy: false, schema: act)
        end
      end

      def component?(name)
        @components.key?(name)
      end

      def params(name)
        @components[name]
      end

      def call(name)
        @calls[name]
      end

      # A runtime call: built-in, library function, action, Action, Query or Mutation.
      def runtime_call?(name)
        @calls.key?(name) || Builtins.reserved_call?(name)
      end

      def component_names
        @components.keys
      end

      private

      def compile_params(d, action_defs, bindable)
        props = d["properties"] || {}
        required = d["required"] || []
        props.map do |key, prop|
          Param.new(name: key, required: required.include?(key), default: Validation.default_value(prop),
            schema: action_defs.empty? ? prop : inline_action_refs(prop, action_defs),
            bindable: bindable.include?(key))
        end
      end

      # {$ref: "#/$defs/ActionExpression"} -> its body, so action slots validate as inline unions.
      def inline_action_refs(node, defs)
        case node
        when Hash
          ref = node["$ref"]
          if ref.is_a?(String)
            return defs.key?(ref) ? inline_action_refs(defs[ref], defs) : node
          end
          node.transform_values { |v| inline_action_refs(v, defs) }
        when Array then node.map { |v| inline_action_refs(v, defs) }
        else node
        end
      end
    end
  end
end
