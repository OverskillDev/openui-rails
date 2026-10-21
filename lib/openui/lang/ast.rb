# frozen_string_literal: true

module OpenUI
  module Lang
    # AST nodes are plain Hashes with a :k discriminant, mirroring the reference
    # parser (packages/lang-core/src/parser/ast.ts):
    #
    #   {k: :comp, name:, args:, fn: true?}   component or @call
    #   {k: :str, v:} {k: :num, v:} {k: :bool, v:} {k: :null}
    #   {k: :arr, els:} {k: :obj, entries: [[key, node], ...]}
    #   {k: :ref, n:} {k: :ph, n:} {k: :state_ref, n:}
    #   {k: :runtime_ref, n:, ref_type: :query | :mutation}
    #   {k: :bin_op, op:, left:, right:} {k: :unary_op, op:, operand:}
    #   {k: :ternary, cond:, then:, else:} {k: :member, obj:, field:}
    #   {k: :index, obj:, index:} {k: :assign, target:, value:}
    module AST
      KINDS = %i[comp str num bool null arr obj ref ph state_ref runtime_ref
        bin_op unary_op ternary member index assign].freeze

      module_function

      def node?(value)
        value.is_a?(Hash) && KINDS.include?(value[:k])
      end

      # Depth-first visit of every node.
      def walk(node, &visit)
        return unless node?(node)
        visit.call(node)
        case node[:k]
        when :comp then node[:args].each { |a| walk(a, &visit) }
        when :arr then node[:els].each { |e| walk(e, &visit) }
        when :obj then node[:entries].each { |(_, v)| walk(v, &visit) }
        when :bin_op
          walk(node[:left], &visit)
          walk(node[:right], &visit)
        when :unary_op then walk(node[:operand], &visit)
        when :ternary
          walk(node[:cond], &visit)
          walk(node[:then], &visit)
          walk(node[:else], &visit)
        when :member then walk(node[:obj], &visit)
        when :index
          walk(node[:obj], &visit)
          walk(node[:index], &visit)
        when :assign then walk(node[:value], &visit)
        end
      end

      # Literal value of a literal node, as [value] so nil can be distinguished
      # from "not a literal" (which returns nil).
      def literal(node)
        case node[:k]
        when :str, :num, :bool then [node[:v]]
        when :null, :ph then [nil]
        when :arr
          vals = node[:els].map { |e| literal(e) }
          vals.all? ? [vals.map(&:first)] : nil
        when :obj
          out = {}
          node[:entries].each do |(key, v)|
            lit = literal(v)
            return nil unless lit
            out[key] = lit.first
          end
          [out]
        end
      end

      # Wrap a plain Ruby value back into a literal node.
      def to_literal(value)
        case value
        when String then {k: :str, v: value}
        when Numeric then {k: :num, v: value}
        when true, false then {k: :bool, v: value}
        when nil then {k: :null}
        when Array then {k: :arr, els: value.map { |v| to_literal(v) }}
        when Hash then {k: :obj, entries: value.map { |key, v| [key.to_s, to_literal(v)] }}
        else {k: :null}
        end
      end

      # Statement name depth-first references.
      def collect_refs(node, out = [])
        walk(node) do |n|
          out << n[:n] if n[:k] == :ref || n[:k] == :runtime_ref
        end
        out
      end

      def collect_state_refs(node, out = [])
        walk(node) { |n| out << n[:n] if n[:k] == :state_ref }
        out.uniq
      end
    end
  end
end
