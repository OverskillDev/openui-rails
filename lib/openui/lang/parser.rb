# frozen_string_literal: true

require "set"

module OpenUI
  module Lang
    # The result of one parse (language.md 9.1 plus the metadata of Appendix B).
    ParseResult = Struct.new(
      :root, :errors, :unresolved, :orphaned, :statement_count, :incomplete, :state,
      :queries, :mutations, :statements, :truncated, :complete,
      keyword_init: true
    ) do
      def root?
        !root.nil?
      end

      # Errors a host should show or send back; warnings and streaming-only
      # conditions are filtered when +complete+ is false (8.2: no-root waits
      # for stream end).
      def reportable_errors
        complete ? errors : errors.reject { |e| e.code == "no-root" || e.code == "missing-required" || e.code == "null-required" }
      end

      def fatal?
        errors.any?(&:fatal?)
      end

      def self.empty(incomplete: true, complete: false)
        new(root: nil, errors: [], unresolved: [], orphaned: [], statement_count: 0, incomplete: incomplete,
          state: {}, queries: {}, mutations: {}, statements: [], truncated: false, complete: complete)
      end
    end

    # Batch parser: the whole text in one pass (language.md sections 1, 2, 8).
    class Parser
      Entry = Struct.new(:id, :fallback)

      attr_reader :schema, :root_name, :functions, :limits, :placeholders

      # @param schema [Schema] compiled library schema
      # @param root [String, nil] the library's root component name (entry rule 2.2)
      # @param functions [Hash{String => #call}] implementations of library functions
      # @param placeholders [Boolean] keep unresolved component references as
      #   Placeholder values so a renderer can show a skeleton (off by default, spec 4 rule 5)
      def initialize(schema, root: nil, functions: {}, limits: Limits.default, placeholders: false)
        @schema = schema
        @root_name = root || schema.root
        @functions = functions
        @limits = limits
        @placeholders = placeholders
      end

      # @return [ParseResult]
      def parse(input, complete: true)
        input = Parser.utf8(input)
        truncated = false
        if limits && input.bytesize > limits.max_input_bytes
          input = input.byteslice(0, limits.max_input_bytes).scrub("")
          truncated = true
        end
        text = Statements.preprocess(input)
        return ParseResult.empty(complete: complete).tap { |r| r.truncated = truncated } if text.empty?

        closed, incomplete = Statements.auto_close(text, max_depth: limits&.max_depth)
        raws = Statements.split(Lexer.tokenize(closed, max_string_length: limits&.max_string_length))
        return ParseResult.empty(incomplete: incomplete, complete: complete) if raws.empty?

        stmt_map = {}
        raws.each do |raw|
          stmt_map[raw.id] = classify(raw)
          break if limits && stmt_map.size >= limits.max_statements
        end
        result = build(stmt_map, incomplete: incomplete, count: stmt_map.size, complete: complete)
        result.truncated = truncated || (limits && raws.length > limits.max_statements)
        if result.truncated && result.errors.none? { |e| e.code == "limit-exceeded" }
          result.errors << Error.new(source: "host", code: "limit-exceeded",
            message: "Response exceeded a host limit; parsing stopped", hint: "Shorten the program")
        end
        result
      end

      # Model output arrives in whatever encoding the transport labelled it with;
      # the language is UTF-8 text.
      def self.utf8(text)
        text = text.to_s
        text = text.dup.force_encoding(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8
        text.valid_encoding? ? text : text.scrub("\uFFFD")
      end

      def builtin_predicate
        @builtin_predicate ||= ->(name) { Builtins.builtin?(name) }
      end

      # Parse one statement's tokens and classify it (2.1).
      def classify(raw)
        expr = ExpressionParser.parse(raw.tokens, builtin: builtin_predicate)
        if expr[:k] == :comp && expr[:name] == "Query"
          {kind: :query, id: raw.id, expr: expr, call: expr[:args]}
        elsif expr[:k] == :comp && expr[:name] == "Mutation"
          {kind: :mutation, id: raw.id, expr: expr, call: expr[:args]}
        elsif raw.id_type == T::STATE_VAR
          {kind: :state, id: raw.id, expr: expr}
        else
          {kind: :value, id: raw.id, expr: expr}
        end
      end

      def component_call?(node)
        node.is_a?(Hash) && node[:k] == :comp && !node[:fn] && !Builtins.builtin?(node[:name]) &&
          !Builtins.reserved_call?(node[:name])
      end

      # Entry: `root`, else the first value statement that calls the root component (2.2).
      def pick_entry(stmt_map)
        return Entry.new("root", false) if stmt_map.key?("root")
        stmt_map.each_value do |s|
          return Entry.new(s[:id], true) if s[:kind] == :value && component_call?(s[:expr]) && s[:expr][:name] == root_name
        end
        nil
      end

      def resolves_to_component_call?(node, syms)
        seen = Set.new
        while node.is_a?(Hash) && node[:k] == :ref && !seen.include?(node[:n])
          seen << node[:n]
          stmt = syms[node[:n]]
          node = stmt && stmt[:expr]
        end
        component_call?(node)
      end

      def contains_component?(node)
        found = false
        AST.walk(node) { |n| found = true if component_call?(n) }
        found
      end

      # Assemble the ParseResult from classified statements.
      # @param pending [Hash, nil] {name:, ids:} a `$name` still growing at the end of a stream
      def build(stmt_map, incomplete:, count:, complete: true, pending: nil)
        entry = pick_entry(stmt_map)
        unreached = Set.new
        stmt_map.each_value do |s|
          next if entry && s[:id] == entry.id
          next unless s[:kind] == :value
          unreached << s[:id]
        end
        queries = {}
        mutations = {}
        stmt_map.each_value do |s|
          case s[:kind]
          when :query
            queries[s[:id]] = {tool: s[:call][0], args: s[:call][1], defaults: s[:call][2], refresh: s[:call][3],
                               deps: s[:call][1] ? AST.collect_state_refs(s[:call][1]) : []}
          when :mutation
            mutations[s[:id]] = {tool: s[:call][0], args: s[:call][1]}
          end
        end

        ctx = Materializer::Context.new(
          syms: stmt_map, schema: schema, errors: [], unresolved: [], visited: Set.new, partial: incomplete,
          current_statement_id: entry&.id, unreached: unreached, state: {}, functions: functions,
          queries: queries, mutations: mutations, limits: limits, element_count: 0, placeholders: placeholders,
          complete: complete
        )
        mat = Materializer.new(ctx)

        # State defaults (5.1), in program order.
        stmt_map.each_value do |s|
          next unless s[:kind] == :state
          ctx.current_statement_id = s[:id]
          ctx.state[s[:id]] = mat.value(s[:expr])
        end
        # Auto-declare every referenced $name with null.
        stmt_map.each_value do |s|
          nodes = case s[:kind]
                  when :state, :value then [s[:expr]]
                  else s[:call]
                  end
          nodes.compact.each do |node|
            AST.collect_state_refs(node).each do |dep|
              next if pending && dep == pending[:name] && pending[:ids].include?(s[:id])
              ctx.state[dep] = nil unless ctx.state.key?(dep)
            end
          end
        end

        root = nil
        if entry
          ctx.current_statement_id = entry.id
          value = Values.unwrap(mat.materialize(stmt_map[entry.id][:expr], :value))
          if value.is_a?(Element)
            root = value
            root.statement_id = entry.id
          end
        end

        # Reachability follows references, not evaluation: both branches of a
        # ternary are reached, and statements referenced from query or mutation
        # arguments are reachable (2.3).
        mark_reachable(stmt_map, entry, queries, mutations, unreached)

        ctx.current_statement_id = entry&.id
        component = root_name.to_s
        if entry.nil?
          Validation.push_issue(ctx, component, "", {code: "no-root", reason: "missing"})
        else
          expr = stmt_map[entry.id][:expr]
          if root.nil? && !resolves_to_component_call?(expr, stmt_map) && !contains_component?(expr)
            Validation.push_issue(ctx, component, "", {code: "no-root", reason: "not-component"})
          elsif entry.fallback
            Validation.push_issue(ctx, component, "", {code: "no-root", reason: root ? "fallback" : "missing"})
          end
        end

        ParseResult.new(
          root: root,
          errors: ctx.errors,
          unresolved: ctx.unresolved.uniq,
          orphaned: entry ? unreached.to_a : [],
          statement_count: count,
          incomplete: incomplete,
          state: ctx.state,
          queries: queries,
          mutations: mutations,
          statements: stmt_map.keys,
          truncated: false,
          complete: complete
        )
      end

      private

      def mark_reachable(stmt_map, entry, queries, mutations, unreached)
        queue = []
        queue.concat(AST.collect_refs(stmt_map[entry.id][:expr])) if entry
        (queries.values + mutations.values).each do |info|
          [info[:tool], info[:args], info[:defaults], info[:refresh]].compact.each { |n| queue.concat(AST.collect_refs(n)) }
        end
        seen = Set.new
        until queue.empty?
          name = queue.shift
          next if seen.include?(name) || !stmt_map.key?(name)
          seen << name
          unreached.delete(name)
          stmt = stmt_map[name]
          queue.concat(AST.collect_refs(stmt[:expr])) if stmt[:expr]
        end
      end
    end
  end
end
