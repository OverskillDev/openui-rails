# frozen_string_literal: true

module OpenUI
  module Lang
    # Turns parsed statements into a tree of Element values: resolves
    # references (language.md 2.3), maps positional arguments to props and
    # validates them (8.4), evaluates expressions, built-ins and library
    # functions statically against the declared state defaults (3), and builds
    # action plans (6.3) without running them. Merges the reference
    # materialize.ts and runtime/evaluator.ts passes; openui-rails has no
    # reactive runtime in v0.1, so the two collapse into one.
    class Materializer
      Context = Struct.new(
        :syms, :schema, :errors, :unresolved, :visited, :partial, :current_statement_id,
        :unreached, :state, :functions, :queries, :mutations, :limits, :element_count, :pending_state_ref,
        :placeholders, :complete,
        keyword_init: true
      )

      attr_reader :ctx

      def initialize(ctx)
        @ctx = ctx
      end

      # Materialize a statement expression in value position.
      def value(node)
        Values.unwrap(materialize(node, :value))
      end

      # The materialized value with Dynamic wrappers kept (for Element detection).
      def materialize(node, position = :value, scope = {})
        case node[:k]
        when :str, :num, :bool then node[:v]
        when :null, :ph then nil
        when :arr then materialize_array(node, position, scope)
        when :obj then node[:entries].to_h { |(k, v)| [k, materialize(v, position, scope)] }
        when :ref then resolve_ref(node[:n], position, scope)
        when :state_ref then Dynamic.new(ctx.state.key?(node[:n]) ? ctx.state[node[:n]] : nil)
        when :assign then Dynamic.new(ctx.state[node[:target]])
        when :runtime_ref then resolve_ref(node[:n], position, scope)
        when :comp then materialize_comp(node, position, scope)
        else Dynamic.new(evaluate_expr(node, scope))
        end
      end

      private

      # Skeletons only exist while the stream is open (spec 4 rule 5 at stream end).
      def placeholders_active?
        ctx.placeholders && !ctx.complete
      end

      def dynamic_node?(node)
        %i[bin_op unary_op ternary member index assign state_ref runtime_ref].include?(node[:k]) ||
          (node[:k] == :comp && (node[:fn] || ctx.schema.runtime_call?(node[:name])))
      end

      def materialize_array(node, position, scope)
        items = []
        node[:els].each do |e|
          next if e[:k] == :ph
          v = materialize(e, position, scope)
          next if v.nil? && (e[:k] == :comp || e[:k] == :ref)
          items << v
        end
        items
      end

      # A bare name refers to the statement with that name (2.3).
      def resolve_ref(name, position, scope)
        return scope[name] if scope.key?(name)
        if ctx.visited.include?(name) || !ctx.syms.key?(name)
          ctx.unresolved << name
          return Placeholder.new(name) if placeholders_active? && position == :value && !ctx.syms.key?(name)
          return nil
        end
        stmt = ctx.syms[name]
        ctx.unreached&.delete(name)
        case stmt[:kind]
        when :query
          q = ctx.queries[name]
          defaults = q && q[:defaults] ? materialize(q[:defaults], :expr, scope) : nil
          return Dynamic.new(Values.unwrap(defaults))
        when :mutation
          return Dynamic.new({"status" => "idle", "data" => nil, "error" => nil})
        end
        ctx.visited << name
        prev = ctx.current_statement_id
        ctx.current_statement_id = name
        begin
          result = materialize(stmt[:expr], position, scope)
          result.statement_id = name if result.is_a?(Element)
          # A statement that is still streaming and does not render yet (it does
          # not validate, or it is itself a half-written reference) keeps a
          # skeleton under its own name instead of blinking out.
          if placeholders_active? && position == :value && stmt[:kind] == :value && (result.nil? || result.is_a?(Placeholder))
            result = Placeholder.new(name)
          end
          result
        ensure
          ctx.current_statement_id = prev
          ctx.visited.delete(name)
        end
      end

      def materialize_comp(node, position, scope)
        name = node[:name]
        schema = ctx.schema

        if node[:fn] && !schema.runtime_call?(name)
          Validation.push_issue(ctx, name, "", {code: "unknown-function"})
          return nil
        end

        if Builtins.reserved_call?(name)
          # Query/Mutation in a value position: inline-reserved. In a computed
          # expression they are null with no error (2.1).
          Validation.push_issue(ctx, name, "", {code: "inline-reserved"}) if position == :value
          return nil
        end

        return Dynamic.new(materialize_call(node, scope)) if schema.runtime_call?(name)

        params = schema.params(name)
        unless params
          Validation.push_issue(ctx, name, "", {code: "unknown-component", available: schema.component_names})
          return nil
        end

        if ctx.limits && ctx.element_count >= ctx.limits.max_elements
          Validation.push_issue(ctx, name, "", {code: "limit-exceeded", limit: "max_elements"}) if ctx.element_count == ctx.limits.max_elements
          ctx.element_count += 1
          return nil
        end
        ctx.element_count += 1

        return build_unvalidated(node, params, scope) if position == :expr

        build_validated(node, params, scope)
      end

      # Catalog component in a computed expression: args map to props, no schema checks (reference parity).
      def build_unvalidated(node, params, scope)
        props = {}
        params.each_with_index do |param, i|
          break if i >= node[:args].length
          props[param.name] = Values.unwrap(materialize(node[:args][i], :value, scope))
        end
        Element.new(type: node[:name], props: props, partial: ctx.partial)
      end

      def build_validated(node, params, scope)
        name = node[:name]
        args = node[:args]
        props = {}
        drop = false
        params.each_with_index do |param, i|
          break if i >= args.length
          arg = args[i]
          value = if param.bindable && arg[:k] == :state_ref
            Binding.new(arg[:n])
          else
            materialize(arg, :value, scope)
          end
          value = strip_placeholders(value, param.schema) if placeholders_active?
          props[param.name] = value
          next if param.schema.nil?
          nxt = Validation.validate_schema_value(value, param.schema, name, "/#{param.name}", ctx)
          if nxt.equal?(Validation::INVALID)
            nxt = Validation.resolve_invalid(param.required, param.default)
            if nxt.equal?(Validation::INVALID)
              drop = true
            elsif nxt.nil?
              props.delete(param.name)
            end
          end
          props[param.name] = nxt unless nxt.equal?(Validation::INVALID) || nxt.nil?
        end

        if args.length > params.length
          Validation.push_issue(ctx, name, "", {code: "excess-args", declared: params.length, got: args.length})
        end

        missing = params.select { |p| p.required && (!props.key?(p.name) || props[p.name].nil?) }
        unless missing.empty?
          still = missing.reject do |p|
            next false if p.default.nil?
            props[p.name] = p.default
            true
          end
          unless still.empty?
            still.each do |p|
              Validation.push_issue(ctx, name, "/#{p.name}", {
                code: props.key?(p.name) ? "null-required" : "missing-required",
                signature: Validation.params_signature(name, params)
              })
            end
            return nil
          end
        end
        return nil if drop

        Element.new(type: name, props: props.transform_values { |v| Values.unwrap(v) }, partial: ctx.partial)
      end

      # Placeholders stand in for components only: a scalar prop or a data list
      # drops them like any unresolved reference.
      def strip_placeholders(value, schema)
        case value
        when Placeholder then Validation.slot_schema?(schema) ? value : nil
        when Array
          items = schema.is_a?(Hash) ? schema["items"] : nil
          keep = !items.is_a?(Hash) || Validation.composite?(items)
          keep ? value : value.reject { |v| v.is_a?(Placeholder) }
        else value
        end
      end

      # ── Calls: built-ins, library functions, steps, Action ────────────────

      def materialize_call(node, scope)
        name = node[:name]
        call = ctx.schema.call(name)
        return nil unless call
        if call.builtin && call.kind == :function
          return each(node, scope) if call.lazy
          args = named_args(node, call.params, scope)
          return Builtins.call_function(name, args)
        end
        return action_call(node, call, scope) if call.kind == :action
        library_function(node, call, scope)
      end

      def named_args(node, params, scope)
        out = {}
        params.each_with_index do |p, i|
          break if i >= node[:args].length
          out[p.name] = Values.unwrap(materialize(node[:args][i], :expr, scope))
        end
        out
      end

      def literal_args_valid?(node, call)
        params = call.params
        if node[:args].length > params.length
          Validation.push_issue(ctx, node[:name], "", {code: "excess-args", declared: params.length, got: node[:args].length})
        end
        invalid = false
        before = ctx.errors.length
        params.each_with_index do |p, i|
          arg = node[:args][i]
          lit = arg ? AST.literal(arg) : [nil]
          next if lit.nil? # runtime arg, checked when evaluated
          if lit.first.nil?
            next if !p.required || !p.default.nil?
            Validation.push_issue(ctx, node[:name], "/#{p.name}", {
              code: arg ? "null-required" : "missing-required",
              signature: Validation.params_signature(node[:name], params)
            })
            invalid = true
            next
          end
          nxt = Validation.validate_schema_value(lit.first, p.schema, node[:name], "/#{p.name}", ctx)
          nxt = Validation.resolve_invalid(p.required, p.default) if nxt.equal?(Validation::INVALID)
          invalid = true if nxt.equal?(Validation::INVALID)
        end
        invalid = true if call.kind == :action && ctx.errors.length > before
        !invalid
      end

      # @Percent(part, total): literal args checked like props at parse time,
      # runtime args when evaluated; a failing call evaluates to null (3.6).
      def library_function(node, call, scope)
        return nil unless literal_args_valid?(node, call)
        fn = ctx.functions && ctx.functions[node[:name]]
        args = call_args(node, call, scope)
        return nil if misses_required?(args, call)
        checked = check_value(args, call.schema && call.schema["params"], node[:name], "")
        return nil if checked.equal?(Validation::INVALID)
        return nil unless fn
        result = begin
          fn.call(**checked.transform_keys(&:to_sym))
        rescue ArgumentError, StandardError => e
          runtime_error("@#{node[:name]} threw: #{e.message}")
          return nil
        end
        returns = call.schema && call.schema["returns"]
        return result unless returns
        checked_result = check_value(result, returns, node[:name], "/returns")
        checked_result.equal?(Validation::INVALID) ? nil : checked_result
      end

      def call_args(node, call, scope)
        args = {}
        required = (call.schema && call.schema.dig("params", "required")) || call.params.select(&:required).map(&:name)
        call.params.each_with_index do |p, i|
          break if i >= node[:args].length
          v = Values.unwrap(materialize(node[:args][i], :expr, scope))
          next if v.nil? && !required.include?(p.name)
          args[p.name] = v
        end
        args
      end

      def misses_required?(args, call)
        call.params.any? { |p| p.required && args[p.name].nil? && p.default.nil? }
      end

      def check_value(value, schema, name, path, strict: false)
        return value unless schema
        sub = Context.new(errors: [], partial: false, schema: ctx.schema, current_statement_id: ctx.current_statement_id)
        checked = Validation.validate_schema_value(value, schema, name, path, sub)
        sub.errors.each { |e| runtime_error("@#{name}: #{e.message}") }
        (strict && !sub.errors.empty?) ? Validation::INVALID : checked
      end

      def runtime_error(message)
        ctx.errors << Error.new(source: "runtime", code: "runtime-error", message: message,
          statement_id: ctx.current_statement_id)
      end

      # Each(array, varName, template): evaluate the template per element with the loop variable in scope.
      def each(node, scope)
        args = node[:args]
        return [] if args.length < 3
        arr = Values.unwrap(materialize(args[0], :expr, scope))
        return [] unless arr.is_a?(Array)
        var = case args[1][:k]
              when :ref then args[1][:n]
              when :str then args[1][:v]
              end
        return [] unless var
        limit = ctx.limits ? ctx.limits.max_each_items : arr.length
        arr.first(limit).map do |item|
          Values.unwrap(materialize(args[2], :expr, scope.merge(var => item)))
        end
      end

      # ── Actions ────────────────────────────────────────────────────────────

      def action_call(node, call, scope)
        name = node[:name]
        if name == "Action"
          list = node[:args].empty? ? [] : Values.unwrap(materialize(node[:args][0], :expr, scope))
          return flatten_plans(list.is_a?(Array) ? list : [])
        end
        if call.builtin
          step = builtin_step(name, node, scope)
          return ActionPlan.new(step ? [step] : [])
        end
        # Custom action: a one-step plan; any invalid argument makes it a no-op.
        return ActionPlan.new([]) unless literal_args_valid?(node, call)
        args = call_args(node, call, scope)
        return ActionPlan.new([]) if misses_required?(args, call)
        params = check_value(args, call.schema && call.schema["params"], name, "", strict: true)
        return ActionPlan.new([]) if params.equal?(Validation::INVALID)
        ActionPlan.new([Step.new(type: :custom_action, data: {name: name, params: params})])
      end

      def builtin_step(name, node, scope)
        args = node[:args]
        case name
        when "ToAssistant"
          named = named_args(node, ctx.schema.call(name).params, scope)
          Step.new(type: :continue_conversation, data: {message: Builtins.js_string(named["message"].nil? ? "" : named["message"]), context: named["context"]})
        when "OpenUrl"
          named = named_args(node, ctx.schema.call(name).params, scope)
          Step.new(type: :open_url, data: {url: Builtins.js_string(named["url"].nil? ? "" : named["url"])})
        when "Run"
          ref = args[0]
          return nil unless ref && ref[:k] == :ref && ctx.syms.key?(ref[:n]) && %i[query mutation].include?(ctx.syms[ref[:n]][:kind])
          Step.new(type: :run, data: {statement_id: ref[:n], ref_type: ctx.syms[ref[:n]][:kind]})
        when "Set"
          return nil if args.length < 2 || args[0][:k] != :state_ref
          Step.new(type: :set, data: {target: args[0][:n], value_ast: args[1],
            value: Values.unwrap(materialize(args[1], :expr, scope))})
        when "Reset"
          targets = args.select { |a| a[:k] == :state_ref }.map { |a| a[:n] }
          targets.empty? ? nil : Step.new(type: :reset, data: {targets: targets})
        end
      end

      # Plans flatten into one; legacy action objects ({type: "open_url", url}) count as steps.
      def flatten_plans(values)
        steps = values.flat_map do |v|
          case v
          when ActionPlan then v.steps
          when Hash
            case v["type"]
            when "open_url" then [Step.new(type: :open_url, data: {url: v["url"].to_s})]
            when "continue_conversation" then [Step.new(type: :continue_conversation, data: {message: "", context: v["context"]})]
            else []
            end
          else []
          end
        end
        ActionPlan.new(steps)
      end

      # ── Expressions (language.md 3.1 to 3.3) ──────────────────────────────

      def evaluate_expr(node, scope)
        case node[:k]
        when :bin_op then binary(node, scope)
        when :unary_op
          v = operand(node[:operand], scope)
          case node[:op]
          when "!" then !Builtins.truthy?(v)
          when "-" then Builtins.normalize_number(-Builtins.to_number(v))
          end
        when :ternary
          Builtins.truthy?(operand(node[:cond], scope)) ? operand(node[:then], scope) : operand(node[:else], scope)
        when :member
          obj = operand(node[:obj], scope)
          member(obj, node[:field])
        when :index
          obj = operand(node[:obj], scope)
          idx = operand(node[:index], scope)
          return nil if obj.nil? || idx.nil?
          case obj
          when Array
            n = Builtins.to_number(idx)
            (n.is_a?(Integer) || n == n.floor) ? (n.to_i >= 0 ? obj[n.to_i] : nil) : nil
          when Hash then obj[Builtins.js_string(idx)]
          else nil
          end
        end
      end

      def operand(node, scope)
        Values.unwrap(materialize(node, :expr, scope))
      end

      def member(obj, field)
        return nil if obj.nil?
        case obj
        when Array
          return obj.length if field == "length"
          obj.map { |item| Builtins.member_get(item, field) }
        when Hash, String then Builtins.member_get(obj, field)
        else nil # a component instance or scalar acts like an object with no fields
        end
      end

      def binary(node, scope)
        op = node[:op]
        if op == "&&"
          l = operand(node[:left], scope)
          return Builtins.truthy?(l) ? operand(node[:right], scope) : l
        end
        if op == "||"
          l = operand(node[:left], scope)
          return Builtins.truthy?(l) ? l : operand(node[:right], scope)
        end
        l = operand(node[:left], scope)
        r = operand(node[:right], scope)
        case op
        when "+"
          if l.is_a?(String) || r.is_a?(String)
            Builtins.js_string(l.nil? ? "" : l) + Builtins.js_string(r.nil? ? "" : r)
          else
            Builtins.normalize_number(Builtins.to_number(l) + Builtins.to_number(r))
          end
        when "-" then Builtins.normalize_number(Builtins.to_number(l) - Builtins.to_number(r))
        when "*" then Builtins.normalize_number(Builtins.to_number(l) * Builtins.to_number(r))
        when "/"
          d = Builtins.to_number(r)
          d.zero? ? 0 : Builtins.normalize_number(Builtins.to_number(l).to_f / d)
        when "%"
          d = Builtins.to_number(r)
          d.zero? ? 0 : Builtins.normalize_number(Builtins.to_number(l).to_f.remainder(d))
        when "==" then Builtins.loose_eq(l, r)
        when "!=" then !Builtins.loose_eq(l, r)
        when ">" then Builtins.to_number(l) > Builtins.to_number(r)
        when "<" then Builtins.to_number(l) < Builtins.to_number(r)
        when ">=" then Builtins.to_number(l) >= Builtins.to_number(r)
        when "<=" then Builtins.to_number(l) <= Builtins.to_number(r)
        end
      end
    end
  end
end
