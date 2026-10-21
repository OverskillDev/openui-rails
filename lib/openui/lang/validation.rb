# frozen_string_literal: true

module OpenUI
  module Lang
    # Validates materialized values against JSON Schema fragments and reports
    # the error codes of language.md section 8. Ported from
    # packages/lang-core/src/parser/validation.ts (MIT).
    module Validation
      INVALID = Object.new.freeze
      SCALARS = %w[string number boolean].freeze

      module_function

      def js_type(value)
        case value
        when nil then "null"
        when String then "string"
        when Numeric then "number"
        when true, false then "boolean"
        when Array then "array"
        else "object"
        end
      end

      def ref_name(s)
        r = s["$ref"]
        r.is_a?(String) ? r.split("/").last : nil
      end

      def composite?(s)
        s.key?("$ref") || s.key?("anyOf") || s.key?("oneOf") || s.key?("allOf")
      end

      # Scalar leaf type/enum info from a JSON Schema object.
      def scalar_info(s)
        return {enum: s["enum"]} if s["enum"].is_a?(Array)
        return {enum: [s["const"]]} if s.key?("const")
        case s["type"]
        when "string" then {type: "string"}
        when "number", "integer" then {type: "number"}
        when "boolean" then {type: "boolean"}
        else {}
        end
      end

      def default_value(property)
        property.is_a?(Hash) ? property["default"] : nil
      end

      # Type label for hints: refs, enums, scalars.
      def type_from_schema(property)
        return nil unless property.is_a?(Hash)
        if (ref = ref_name(property))
          return ref
        end
        leaf = scalar_info(property)
        return leaf[:enum].map { |v| v.to_json }.join("|") if leaf[:enum]
        return leaf[:type] if leaf[:type]
        property["type"].is_a?(String) ? property["type"] : nil
      end

      # `Header(title*: string, variant: "a"|"b")`; * marks required.
      def params_signature(component, params)
        rendered = params.map do |p|
          type = type_from_schema(p.schema)
          marked = p.required ? "#{p.name}*" : p.name
          type ? "#{marked}: #{type}" : marked
        end
        "#{component}(#{rendered.join(", ")})"
      end

      def check_mismatch(value, info)
        actual = js_type(value)
        if info[:enum]
          return nil unless SCALARS.include?(actual)
          return nil if info[:enum].include?(value)
          return {expected: "one of [#{info[:enum].map { |v| v.to_json }.join(", ")}]", actual: value.to_json}
        end
        if info[:type] && info[:type] != actual
          return {expected: info[:type], actual: actual}
        end
        nil
      end

      def message_for(component, path, issue)
        case issue[:code]
        when "type-mismatch" then "field \"#{path}\" expects #{issue[:expected]} but got #{issue[:actual]}"
        when "missing-required" then "missing required field \"#{path}\"#{issue[:signature] ? " — signature: #{issue[:signature]}" : ""}"
        when "null-required" then "required field \"#{path}\" cannot be null#{issue[:signature] ? " — signature: #{issue[:signature]}" : ""}"
        when "unknown-component"
          avail = issue[:available]
          "Unknown component \"#{component}\" — not found in catalog or builtins#{(avail && !avail.empty?) ? ". Available components: #{avail.join(", ")}" : ""}"
        when "inline-reserved" then "#{component}() must be declared as a top-level statement, not used inline as a value"
        when "excess-args" then "#{component} takes #{issue[:declared]} arg(s), got #{issue[:got]} (#{issue[:got] - issue[:declared]} excess dropped)"
        when "unknown-function" then "Unknown function \"@#{component}\": not a built-in or action step. The call evaluates to null"
        when "no-root"
          case issue[:reason]
          when "not-component" then "root does not evaluate to a component"
          when "fallback" then "No root statement. Rendering the first statement that calls the root component #{component}"
          else component.to_s.empty? ? "No root statement" : "No root statement, and no statement calls the root component #{component}"
          end
        when "limit-exceeded" then "Response exceeded the host limit #{issue[:limit]}; parsing stopped"
        else issue[:code]
        end
      end

      def hint_for(component, issue, ctx)
        case issue[:code]
        when "missing-required", "null-required" then issue[:signature] ? "Signature: #{issue[:signature]}. * marks required" : nil
        when "unknown-component" then issue[:available] && !issue[:available].empty? ? "Available components: #{issue[:available].join(", ")}" : nil
        when "type-mismatch" then "Expected #{issue[:expected]}"
        when "unknown-function" then "Use only the listed @functions and @actions"
        else nil
        end
      end

      # Append an error to +ctx.errors+, deriving its message from the issue.
      def push_issue(ctx, component, path, issue)
        source = (issue[:code] == "limit-exceeded") ? "host" : "parser"
        ctx.errors << Error.new(
          source: source,
          code: issue[:code],
          component: component,
          path: path,
          message: message_for(component, path, issue),
          statement_id: ctx.current_statement_id,
          hint: hint_for(component, issue, ctx),
          severity: (issue[:code] == "no-root" && issue[:reason] == "fallback") ? "warning" : nil
        )
      end

      # invalid value: schema default wins; else INVALID when required, nil (omit) when optional.
      def resolve_invalid(required, default)
        return default unless default.nil?
        required ? INVALID : nil
      end

      def dynamic?(value)
        value.is_a?(Dynamic) || value.is_a?(Binding) || value.is_a?(ActionPlan) || value.is_a?(Placeholder)
      end

      # A slot that can hold a component (a $ref, or a union of $refs), or a list of them.
      def slot_schema?(s)
        return false unless s.is_a?(Hash)
        return true if composite?(s)
        s["type"] == "array" && (!s["items"].is_a?(Hash) || composite?(s["items"]))
      end

      def validate_element_position(element, s, component, path, ctx)
        return false if composite?(s)
        if s["type"].is_a?(String) || s["enum"].is_a?(Array) || s.key?("const")
          push_issue(ctx, component, path, {code: "type-mismatch",
            expected: s["type"].is_a?(String) ? s["type"] : "a literal value",
            actual: "component \"#{element.type}\""})
          return true
        end
        false
      end

      def slot_ref_names(s)
        (s["anyOf"] || s["oneOf"] || [s]).map { |o| o.is_a?(Hash) ? ref_name(o) : nil }
      end

      def only_component_slot?(s, ctx)
        names = slot_ref_names(s)
        !names.empty? && names.all? { |n| n && ctx.schema.component?(n) }
      end

      def validate_object(value, s, component, path, ctx)
        unless value.is_a?(Hash)
          push_issue(ctx, component, path, {code: "type-mismatch", expected: "object", actual: js_type(value)})
          return INVALID
        end
        props = s["properties"].is_a?(Hash) ? s["properties"] : {}
        required = s["required"].is_a?(Array) ? s["required"] : []
        out = nil
        invalid = false
        unless ctx.partial
          required.each do |key|
            present = value.key?(key)
            next unless !present || value[key].nil?
            fallback = default_value(props[key])
            unless fallback.nil?
              (out ||= value.dup)[key] = fallback
              next
            end
            push_issue(ctx, component, "#{path}/#{key}", {code: present ? "null-required" : "missing-required"})
            invalid = true
          end
        end
        props.each_key do |key|
          next unless value.key?(key)
          sub = props[key]
          nxt = validate_schema_value(value[key], sub, component, "#{path}/#{key}", ctx)
          if nxt.equal?(INVALID)
            nxt = resolve_invalid(required.include?(key), default_value(sub))
            if nxt.equal?(INVALID)
              invalid = true
              next
            end
          end
          next if nxt.equal?(value[key])
          out ||= value.dup
          if nxt.nil?
            out.delete(key)
          else
            out[key] = nxt
          end
        end
        invalid ? INVALID : (out || value)
      end

      def validate_array(value, s, component, path, ctx)
        unless value.is_a?(Array)
          push_issue(ctx, component, path, {code: "type-mismatch", expected: "array", actual: js_type(value)})
          return INVALID
        end
        items = s["items"]
        return value unless items.is_a?(Hash)
        out = nil
        value.each_with_index do |item, i|
          nxt = validate_schema_value(item, items, component, "#{path}/#{i}", ctx)
          out ||= value[0...i] unless nxt.equal?(item)
          out << nxt if out && !nxt.equal?(INVALID)
        end
        out || value
      end

      def validate_leaf(value, s, component, path, ctx)
        leaf = scalar_info(s)
        return false if leaf[:type].nil? && leaf[:enum].nil?
        return false if leaf[:enum] && ctx.partial
        mismatch = check_mismatch(value, leaf)
        if mismatch
          push_issue(ctx, component, path, {code: "type-mismatch"}.merge(mismatch))
          return true
        end
        false
      end

      # Recursively validate a value against a JSON Schema fragment. Returns the
      # value, a cleaned copy, or INVALID. Dynamic values (expressions, bindings,
      # action plans) are the runtime's business and pass through.
      def validate_schema_value(value, schema, component, path, ctx)
        return value unless schema.is_a?(Hash)
        return value if value.nil?
        return value if dynamic?(value)
        if value.is_a?(Element)
          return validate_element_position(value, schema, component, path, ctx) ? INVALID : value
        end
        if composite?(schema)
          return value unless only_component_slot?(schema, ctx)
          push_issue(ctx, component, path, {code: "type-mismatch",
            expected: slot_ref_names(schema).join(" | "),
            actual: value.is_a?(Array) ? "array" : (value.is_a?(Hash) ? "plain object" : js_type(value))})
          return INVALID
        end
        case schema["type"]
        when "object" then validate_object(value, schema, component, path, ctx)
        when "array" then validate_array(value, schema, component, path, ctx)
        else validate_leaf(value, schema, component, path, ctx) ? INVALID : value
        end
      end
    end
  end
end
