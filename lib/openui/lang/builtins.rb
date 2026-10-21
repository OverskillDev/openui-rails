# frozen_string_literal: true

module OpenUI
  module Lang
    # Built-in functions and action steps (language.md 3.4, 6.3) and the JS
    # coercion rules clients must reproduce (3.1, 3.2). Ported from
    # packages/lang-core/src/parser/builtins.ts and runtime/evaluator.ts (MIT).
    module Builtins
      module_function

      # ── Coercion (ECMA-262 ToNumber / ToString / ToBoolean) ───────────────

      # String → JS number, or nil for NaN.
      def js_number(str)
        s = str.strip
        return 0 if s.empty?
        return Float::INFINITY if s == "Infinity" || s == "+Infinity"
        return -Float::INFINITY if s == "-Infinity"
        if s.match?(/\A[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\z/)
          normalize_number(Float(s))
        elsif s.match?(/\A0[xX][0-9a-fA-F]+\z/)
          s.to_i(16)
        elsif s.match?(/\A0[bB][01]+\z/)
          s[2..].to_i(2)
        elsif s.match?(/\A0[oO][0-7]+\z/)
          s[2..].to_i(8)
        end
      end

      # toNumber: numbers as is, strings parsed or 0, true 1, everything else 0.
      def to_number(val)
        case val
        when Integer then val
        when Float then val.nan? ? 0 : val
        when String then js_number(val) || 0
        when true then 1
        else 0
        end
      end

      # A whole Float becomes an Integer so tables show 3 where JS shows 3.
      def normalize_number(n)
        return n unless n.is_a?(Float)
        return n if n.nan? || n.infinite?
        (n == n.floor && n.abs < 1e15) ? n.to_i : n
      end

      # ECMAScript ToString for the values the language produces.
      def js_string(val)
        case val
        when nil then "null"
        when String then val
        when Integer then val.to_s
        when Float
          return "NaN" if val.nan?
          return (val > 0 ? "Infinity" : "-Infinity") if val.infinite?
          n = normalize_number(val)
          n.is_a?(Integer) ? n.to_s : n.to_s
        when true then "true"
        when false then "false"
        when Array then val.map { |v| v.nil? ? "" : js_string(v) }.join(",")
        when Hash then "[object Object]"
        else "[object Object]"
        end
      end

      # ToBoolean: false, 0, "", null, NaN are falsy; arrays, objects, components are truthy.
      def truthy?(val)
        case val
        when nil, false then false
        when Integer then val != 0
        when Float then !(val.zero? || val.nan?)
        when String then !val.empty?
        else true
        end
      end

      # IsLooselyEqual for the value kinds the language produces.
      def loose_eq(a, b)
        a = (a ? 1 : 0) if a == true || a == false
        b = (b ? 1 : 0) if b == true || b == false
        return true if a.nil? && b.nil?
        return false if a.nil? || b.nil?
        if a.is_a?(Numeric) && b.is_a?(String)
          n = js_number(b)
          return !n.nil? && a == n
        end
        if a.is_a?(String) && b.is_a?(Numeric)
          n = js_number(a)
          return !n.nil? && n == b
        end
        return a == b if (a.is_a?(Numeric) && b.is_a?(Numeric)) || (a.is_a?(String) && b.is_a?(String))
        a.equal?(b)
      end

      # Dot-path field read used by @Sort and @Filter ("customer.name").
      def resolve_field(obj, path)
        return nil if path.nil? || path.empty? || obj.nil?
        parts = path.split(".")
        cur = obj
        parts.each do |p|
          return nil if cur.nil?
          cur = member_get(cur, p)
        end
        cur
      end

      # obj.field for one segment, the JS way: arrays by index or length, objects by key.
      def member_get(obj, field)
        case obj
        when Hash then obj[field]
        when Array
          return obj.length if field == "length"
          field.match?(/\A\d+\z/) ? obj[field.to_i] : nil
        when String
          field == "length" ? obj.length : nil
        end
      end

      # localeCompare with no arguments: accents and case are secondary and
      # tertiary differences, lowercase sorts before uppercase.
      def collation_key(str)
        s = str.to_s
        base = s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "")
        [base.downcase, s.unicode_normalize(:nfd).downcase, s.chars.map { |c| (c == c.downcase) ? 0 : 1 }]
      end

      def numeric_like?(v)
        v.is_a?(Numeric) || (v.is_a?(String) && !v.empty? && !js_number(v).nil?)
      end

      # ── Functions ──────────────────────────────────────────────────────────

      FUNCTION_DEFS = [
        {name: "Count", signature: "Count(array: any[]) → number", description: "Returns array length", params: %w[array]},
        {name: "First", signature: "First(array: any[]) → any", description: "Returns first element of array", params: %w[array]},
        {name: "Last", signature: "Last(array: any[]) → any", description: "Returns last element of array", params: %w[array]},
        {name: "Sum", signature: "Sum(numbers: number[]) → number", description: "Sum of numeric array", params: %w[numbers]},
        {name: "Avg", signature: "Avg(numbers: number[]) → number", description: "Average of numeric array", params: %w[numbers]},
        {name: "Min", signature: "Min(numbers: number[]) → number", description: "Minimum value in array", params: %w[numbers]},
        {name: "Max", signature: "Max(numbers: number[]) → number", description: "Maximum value in array", params: %w[numbers]},
        {name: "Sort", signature: 'Sort(array: any[], field: string, direction?: "asc" | "desc") → any[]',
         description: 'Sort array by field. Direction: "asc" (default) or "desc"', params: %w[array field direction]},
        {name: "Filter", signature: 'Filter(array: any[], field: string, operator: "==" | "!=" | ">" | "<" | ">=" | "<=" | "contains", value: any) → any[]',
         description: "Filter array by field value", params: %w[array field operator value]},
        {name: "Round", signature: "Round(number: number, decimals?: number) → number", description: "Round to N decimal places (default 0)", params: %w[number decimals]},
        {name: "Abs", signature: "Abs(number: number) → number", description: "Absolute value", params: %w[number]},
        {name: "Floor", signature: "Floor(number: number) → number", description: "Round down to nearest integer", params: %w[number]},
        {name: "Ceil", signature: "Ceil(number: number) → number", description: "Round up to nearest integer", params: %w[number]},
        {name: "Each", signature: "Each(array: any[], varName: string, template: any)",
         description: "Evaluate template for each element. varName is the loop variable — use it ONLY inside the template expression (inline). Do NOT create a separate statement for the template.",
         params: %w[array varName template], lazy: true}
      ].freeze

      FUNCTIONS = FUNCTION_DEFS.to_h { |d| [d[:name], d] }.freeze

      STEP_DEFS = [
        {name: "Run", signature: "Run(ref: Query | Mutation)", description: "Execute a Mutation or re-fetch a Query (ref must be a declared Query/Mutation)", params: %w[ref], lazy: true},
        {name: "ToAssistant", signature: "ToAssistant(message: string, context?: any)",
         description: 'Send a message to the assistant (for conversational buttons like "Tell me more", "Explain this"). The optional context is any value (object, array, string, number) passed to the assistant as hidden data, e.g. @ToAssistant("Show details", {orderId: 42})',
         params: %w[message context]},
        {name: "OpenUrl", signature: "OpenUrl(url: string)", description: "Navigate to a URL", params: %w[url]},
        {name: "Set", signature: "Set(variable: $variable, value: any)", description: "Set a $variable to a specific value", params: %w[variable value], lazy: true},
        {name: "Reset", signature: "Reset(variable: $variable)",
         description: 'Reset $variables to their declared defaults; pass several to reset each (e.g. @Reset($title, $priority) restores $title="" and $priority="medium")',
         params: %w[variable], lazy: true}
      ].freeze

      STEPS = STEP_DEFS.to_h { |d| [d[:name], d] }.freeze

      RESERVED_CALLS = %w[Query Mutation].freeze
      ACTION_WRAPPER = "Action"

      # Every name a library may not use for a component, function or action.
      RESERVED_NAMES = (FUNCTIONS.keys + STEPS.keys + RESERVED_CALLS + [ACTION_WRAPPER] + %w[true false null]).freeze

      def builtin?(name)
        FUNCTIONS.key?(name) || STEPS.key?(name) || name == ACTION_WRAPPER
      end

      def reserved_call?(name)
        RESERVED_CALLS.include?(name)
      end

      def step?(name)
        STEPS.key?(name) || name == ACTION_WRAPPER
      end

      # JSON Schema for the action $defs every library carries (prompt.md 2.3).
      def action_defs
        open_url = {"type" => "object", "properties" => {"type" => {"type" => "string", "const" => "open_url"}, "url" => {"type" => "string"}}, "required" => %w[type url]}
        to_assistant = {"type" => "object", "properties" => {"type" => {"type" => "string", "const" => "continue_conversation"}, "context" => {"type" => "string"}}, "required" => %w[type]}
        {
          "ActionExpression" => {"anyOf" => [open_url, to_assistant, {"type" => "object", "properties" => {"type" => {"type" => "string"}, "params" => {"type" => "object"}}, "required" => %w[type]}]},
          "OpenUrl" => open_url,
          "ToAssistant" => to_assistant
        }
      end

      # ── Implementations ───────────────────────────────────────────────────

      def call_function(name, args)
        case name
        when "Count" then (a = args["array"]).is_a?(Array) ? a.length : 0
        when "First" then (a = args["array"]).is_a?(Array) ? a.first : nil
        when "Last" then (a = args["array"]).is_a?(Array) ? a.last : nil
        when "Sum" then (a = args["numbers"]).is_a?(Array) ? normalize_number(a.sum { |v| to_number(v) }) : 0
        when "Avg"
          a = args["numbers"]
          (a.is_a?(Array) && !a.empty?) ? normalize_number(a.sum { |v| to_number(v) }.to_f / a.length) : 0
        when "Min"
          a = args["numbers"]
          (a.is_a?(Array) && !a.empty?) ? normalize_number(a.map { |v| to_number(v) }.min) : 0
        when "Max"
          a = args["numbers"]
          (a.is_a?(Array) && !a.empty?) ? normalize_number(a.map { |v| to_number(v) }.max) : 0
        when "Sort" then sort(args["array"], args["field"], args["direction"])
        when "Filter" then filter(args["array"], args["field"], args["operator"], args["value"])
        when "Round"
          num = to_number(args["number"]).to_f
          d = args["decimals"].nil? ? 0 : to_number(args["decimals"]).to_i
          factor = 10.0**d
          normalize_number((num * factor + 0.5).floor / factor)
        when "Abs" then normalize_number(to_number(args["number"]).abs)
        when "Floor" then normalize_number(to_number(args["number"]).to_f.floor)
        when "Ceil" then normalize_number(to_number(args["number"]).to_f.ceil)
        end
      end

      def sort(array, field, direction)
        return array unless array.is_a?(Array)
        f = field.to_s
        desc = direction.to_s == "desc"
        keyed = array.each_with_index.map do |item, idx|
          v = f.empty? ? item : resolve_field(item, f)
          [v, idx, item]
        end
        sorted = keyed.sort do |(av, ai, _), (bv, bi, _)|
          cmp = if numeric_like?(av) && numeric_like?(bv)
            to_number(av) <=> to_number(bv)
          else
            collation_key(av.nil? ? "" : js_string(av)) <=> collation_key(bv.nil? ? "" : js_string(bv))
          end
          cmp = -cmp if desc
          cmp.zero? ? ai <=> bi : cmp
        end
        sorted.map(&:last)
      end

      def filter(array, field, operator, value)
        return [] unless array.is_a?(Array)
        f = field.to_s
        op = operator.nil? ? "==" : operator.to_s
        array.select do |item|
          v = f.empty? ? item : resolve_field(item, f)
          case op
          when "==" then loose_eq(v, value)
          when "!=" then !loose_eq(v, value)
          when ">" then to_number(v) > to_number(value)
          when "<" then to_number(v) < to_number(value)
          when ">=" then to_number(v) >= to_number(value)
          when "<=" then to_number(v) <= to_number(value)
          when "contains" then js_string(v.nil? ? "" : v).include?(js_string(value.nil? ? "" : value))
          else false
          end
        end
      end
    end
  end
end
