# frozen_string_literal: true

module OpenUI
  class Library
    # Argument types for the library DSL. Each type knows its JSON Schema
    # fragment (prompt.md 2.3) and its prompt signature (prompt.md 5.1).
    module Types
      class Base
        def optional
          Optional.new(self)
        end

        def optional?
          false
        end

        def inner
          self
        end

        def component_names(_library)
          []
        end
      end

      class Optional < Base
        attr_reader :inner

        def initialize(inner)
          @inner = inner
        end

        def optional?
          true
        end

        def to_json_schema(library)
          inner.to_json_schema(library)
        end

        def signature(library)
          inner.signature(library)
        end

        def component_names(library)
          inner.component_names(library)
        end
      end

      class Scalar < Base
        attr_reader :kind

        def initialize(kind)
          @kind = kind
        end

        def to_json_schema(_library)
          case kind
          when :string then {"type" => "string"}
          when :number then {"type" => "number"}
          when :boolean then {"type" => "boolean"}
          else {}
          end
        end

        def signature(_library)
          kind.to_s
        end
      end

      class Enum < Base
        attr_reader :values

        def initialize(values)
          raise Lang::LibraryError, "enum needs at least one value" if values.empty?
          @values = values.map(&:to_s)
        end

        def to_json_schema(_library)
          {"type" => "string", "enum" => values}
        end

        def signature(_library)
          values.map { |v| "\"#{v}\"" }.join(" | ")
        end
      end

      class List < Base
        attr_reader :of

        def initialize(of)
          @of = of
        end

        def to_json_schema(library)
          {"type" => "array", "items" => of.to_json_schema(library)}
        end

        def signature(library)
          inner_sig = of.signature(library)
          of.union?(library) ? "(#{inner_sig})[]" : "#{inner_sig}[]"
        end

        def component_names(library)
          of.component_names(library)
        end
      end

      class ObjectType < Base
        attr_reader :fields

        # @param fields [Hash{String => Base}] field name to type; Optional types are optional keys
        def initialize(fields)
          @fields = fields.transform_keys(&:to_s)
        end

        def to_json_schema(library)
          {
            "type" => "object",
            "properties" => fields.transform_values { |t| t.to_json_schema(library) },
            "required" => fields.reject { |_, t| t.optional? }.keys
          }
        end

        def signature(library)
          "{" + fields.map { |name, t| "#{name}#{t.optional? ? "?" : ""}: #{t.signature(library)}" }.join(", ") + "}"
        end

        def component_names(library)
          fields.values.flat_map { |t| t.component_names(library) }
        end
      end

      # A slot that takes components: named ones, or every component in the library.
      class Slot < Base
        attr_reader :names

        def initialize(names)
          @names = names.map(&:to_s)
        end

        def any?
          names.empty?
        end

        def component_names(library)
          any? ? library.components.keys : names
        end

        def union?(library)
          component_names(library).length > 1
        end

        def to_json_schema(library)
          refs = component_names(library).map { |n| {"$ref" => "#/$defs/#{n}"} }
          refs.length == 1 ? refs.first : {"anyOf" => refs}
        end

        def signature(library)
          component_names(library).join(" | ")
        end
      end

      # An action prop: any action (ActionExpression) or a restricted set.
      class ActionSlot < Base
        attr_reader :names

        def initialize(names)
          @names = names.map(&:to_s)
        end

        def any?
          names.empty?
        end

        def union?(_library)
          names.length > 1
        end

        def to_json_schema(_library)
          return {"$ref" => "#/$defs/ActionExpression"} if any?
          refs = names.map { |n| {"$ref" => "#/$defs/#{n}"} }
          refs.length == 1 ? refs.first : {"anyOf" => refs}
        end

        def signature(_library)
          any? ? "ActionExpression" : names.map { |n| "@#{n}" }.join(" | ")
        end
      end

      # A type reconstructed from a JSON Schema fragment (from_spec libraries).
      class FromSchema < Base
        attr_reader :schema

        def initialize(schema)
          @schema = schema
        end

        def to_json_schema(_library)
          schema
        end

        def union?(library)
          signature(library).include?(" | ")
        end

        def signature(library)
          Types.signature_from_schema(schema, library)
        end
      end

      Base.class_eval do
        def union?(_library)
          false
        end
      end

      module_function

      # Prompt type string for a JSON Schema fragment (prompt.md 5.1, 2.4).
      def signature_from_schema(s, library)
        return "any" unless s.is_a?(Hash)
        if (ref = s["$ref"]).is_a?(String)
          name = ref.split("/").last
          return "ActionExpression" if name == "ActionExpression"
          return "@#{name}" if library.action_name?(name)
          return name
        end
        if (opts = s["anyOf"] || s["oneOf"]).is_a?(Array)
          return opts.map { |o| signature_from_schema(o, library) }.join(" | ")
        end
        if s["enum"].is_a?(Array)
          return s["enum"].map { |v| "\"#{v}\"" }.join(" | ")
        end
        if s.key?("const")
          v = s["const"]
          return v.is_a?(String) ? "\"#{v}\"" : v.to_s
        end
        case s["type"]
        when "string" then "string"
        when "number", "integer" then "number"
        when "boolean" then "boolean"
        when "array"
          items = s["items"]
          return "any[]" unless items.is_a?(Hash)
          inner = signature_from_schema(items, library)
          (items["anyOf"] || items["oneOf"]) ? "(#{inner})[]" : "#{inner}[]"
        when "object"
          props = s["properties"]
          if props.is_a?(Hash) && !props.empty?
            required = s["required"] || []
            # A field with a default counts as optional (prompt.md 3.1).
            opt = ->(k, v) { !required.include?(k) || (v.is_a?(Hash) && v.key?("default")) }
            "{" + props.map { |k, v| "#{k}#{opt.call(k, v) ? "?" : ""}: #{signature_from_schema(v, library)}" }.join(", ") + "}"
          elsif s["additionalProperties"].is_a?(Hash)
            "Record<string, #{signature_from_schema(s["additionalProperties"], library)}>"
          else
            "{}"
          end
        else
          "any"
        end
      end
    end
  end
end
