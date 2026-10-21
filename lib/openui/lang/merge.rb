# frozen_string_literal: true

require "set"

module OpenUI
  module Lang
    # Edit mode (language.md section 7): merge a patch of changed statements
    # into the current program by name, delete with `name = null`, then drop
    # what `root` no longer reaches. Ported from merge.ts (MIT), with the
    # parser's statement boundaries (1.4) including multi-line ternaries.
    module Merge
      module_function

      # Statement source strings, split with the parser's boundary rules.
      def split_source(input)
        stmts = []
        depth = 0
        ternary = 0
        in_str = nil
        esc = false
        start = 0
        i = 0
        len = input.length
        while i < len
          c = input[i]
          if esc
            esc = false
          elsif c == "\\" && in_str
            esc = true
          elsif in_str
            in_str = nil if c == in_str
          elsif c == '"' || c == "'"
            in_str = c
          else
            case c
            when "(", "[", "{" then depth += 1
            when ")", "]", "}" then depth = [0, depth - 1].max
            when "?" then ternary += 1 if depth.zero?
            when ":" then ternary -= 1 if depth.zero? && ternary.positive?
            when "\n"
              if depth <= 0 && ternary <= 0
                peek = i + 1
                peek += 1 while peek < len && [" ", "\t", "\r", "\n"].include?(input[peek])
                unless peek < len && (input[peek] == "?" || (input[peek] == ":" && ternary.positive?))
                  s = input[start...i].strip
                  stmts << s unless s.empty?
                  start = i + 1
                end
              end
            end
          end
          i += 1
        end
        tail = input[start..].to_s.strip
        stmts << tail unless tail.empty?
        stmts
      end

      def parse_statements(input)
        trimmed = input.strip
        return [] if trimmed.empty?
        builtin = ->(n) { Builtins.builtin?(n) }
        split_source(trimmed).filter_map do |raw|
          stmt = Statements.split(Lexer.tokenize(raw)).first
          next unless stmt
          {id: stmt.id, ast: ExpressionParser.parse(stmt.tokens, builtin: builtin), raw: raw}
        end
      end

      # Remove statements `root` cannot reach; `$state` is always kept.
      def gc_unreachable(order, merged, asts, root_id)
        return unless asts.key?(root_id)
        reachable = Set.new([root_id])
        queue = [root_id]
        until queue.empty?
          id = queue.pop
          ast = asts[id]
          next unless ast
          AST.collect_refs(ast).each do |ref|
            next if reachable.include?(ref) || !asts.key?(ref)
            reachable << ref
            queue << ref
          end
        end
        order.each { |id| reachable << id if id.start_with?("$") }
        order.reverse_each do |id|
          next if reachable.include?(id)
          merged.delete(id)
          order.delete(id)
        end
      end

      # @return [String] the merged program text
      def merge_statements(existing, patch, root_id: "root")
        existing_stmts = parse_statements(existing)
        patch_stmts = parse_statements(Statements.strip_fences(patch.strip))
        return patch_stmts.map { |s| s[:raw] }.join("\n") if existing_stmts.empty?
        return existing if patch_stmts.empty?

        merged = {}
        asts = {}
        order = []
        existing_stmts.each do |s|
          merged[s[:id]] = s[:raw]
          asts[s[:id]] = s[:ast]
          order << s[:id]
        end
        patch_stmts.each do |s|
          if s[:ast][:k] == :null
            merged.delete(s[:id])
            asts.delete(s[:id])
            order.delete(s[:id])
            next
          end
          order << s[:id] unless merged.key?(s[:id])
          merged[s[:id]] = s[:raw]
          asts[s[:id]] = s[:ast]
        end
        gc_unreachable(order, merged, asts, root_id)
        order.select { |id| merged.key?(id) }.map { |id| merged[id] }.join("\n")
      end
    end
  end
end
