# frozen_string_literal: true

module OpenUI
  module Lang
    # Pratt (top-down operator precedence) parser for one statement's tokens.
    # Ported from packages/lang-core/src/parser/expressions.ts (MIT).
    # Precedence follows language.md section 1.5.
    class ExpressionParser
      PREC_TERNARY = 1
      PREC_OR = 2
      PREC_AND = 3
      PREC_EQ = 4
      PREC_CMP = 5
      PREC_ADD = 6
      PREC_MUL = 7
      PREC_UNARY = 8
      PREC_MEMBER = 9

      INFIX_PREC = {
        T::QUESTION => PREC_TERNARY,
        T::OR => PREC_OR,
        T::AND => PREC_AND,
        T::EQEQ => PREC_EQ, T::NOTEQ => PREC_EQ,
        T::GT => PREC_CMP, T::LT => PREC_CMP, T::GTE => PREC_CMP, T::LTE => PREC_CMP,
        T::PLUS => PREC_ADD, T::MINUS => PREC_ADD,
        T::STAR => PREC_MUL, T::SLASH => PREC_MUL, T::PERCENT => PREC_MUL,
        T::DOT => PREC_MEMBER, T::LBRACK => PREC_MEMBER
      }.freeze

      BIN_OPS = {
        T::PLUS => ["+", PREC_ADD], T::MINUS => ["-", PREC_ADD],
        T::STAR => ["*", PREC_MUL], T::SLASH => ["/", PREC_MUL], T::PERCENT => ["%", PREC_MUL],
        T::EQEQ => ["==", PREC_EQ], T::NOTEQ => ["!=", PREC_EQ],
        T::GT => [">", PREC_CMP], T::LT => ["<", PREC_CMP], T::GTE => [">=", PREC_CMP], T::LTE => ["<=", PREC_CMP],
        T::AND => ["&&", PREC_AND], T::OR => ["||", PREC_OR]
      }.freeze

      EOF_TOKEN = Token.new(T::EOF).freeze

      # @param tokens [Array<Token>]
      # @param builtin? [#call] predicate: is this PascalCase name a built-in call (not a component)?
      def self.parse(tokens, builtin:)
        new(tokens, builtin: builtin).parse
      end

      def initialize(tokens, builtin:)
        @tokens = tokens
        @pos = 0
        @builtin = builtin
      end

      def parse
        parse_expr(0)
      end

      private

      def cur
        @tokens[@pos] || EOF_TOKEN
      end

      def peek(offset = 1)
        @tokens[@pos + offset] || EOF_TOKEN
      end

      def adv
        tok = cur
        @pos += 1
        tok
      end

      def eat(type)
        @pos += 1 if cur.type == type
      end

      def infix_prec(tok)
        INFIX_PREC[tok.type] || 0
      end

      def parse_expr(min_prec = 0)
        left = parse_prefix
        left = parse_infix(left) while infix_prec(cur) > min_prec
        left
      end

      def parse_prefix
        tok = cur
        case tok.type
        when T::STR then adv; {k: :str, v: tok.value}
        when T::NUM then adv; {k: :num, v: tok.value}
        when T::TRUE then adv; {k: :bool, v: true}
        when T::FALSE then adv; {k: :bool, v: false}
        when T::NULL then adv; {k: :null}
        when T::LBRACK then parse_arr
        when T::LBRACE then parse_obj
        when T::STATE_VAR
          name = tok.value
          adv
          if cur.type == T::EQUALS
            adv
            value = parse_expr(0)
            return {k: :assign, target: name, value: value}
          end
          {k: :state_ref, n: name}
        when T::TYPE
          name = tok.value
          # Built-ins need the @ prefix; only Action is exempt (spec 1.5).
          if peek.type == T::LPAREN && (!@builtin.call(name) || name == "Action")
            return parse_comp
          end
          adv
          {k: :ref, n: name}
        when T::BUILTIN_CALL
          if peek.type == T::LPAREN
            call = parse_comp
            call[:fn] = true if call[:k] == :comp && !@builtin.call(call[:name])
            return call
          end
          adv
          {k: :ref, n: tok.value}
        when T::IDENT then adv; {k: :ref, n: tok.value}
        when T::NOT
          adv
          {k: :unary_op, op: "!", operand: parse_expr(PREC_UNARY)}
        when T::MINUS
          adv
          {k: :unary_op, op: "-", operand: parse_expr(PREC_UNARY)}
        when T::LPAREN
          adv
          inner = parse_expr(0)
          eat(T::RPAREN)
          inner
        else
          adv
          {k: :null}
        end
      end

      def parse_infix(left)
        tok = cur
        if (op = BIN_OPS[tok.type])
          adv
          return {k: :bin_op, op: op[0], left: left, right: parse_expr(op[1])}
        end

        case tok.type
        when T::QUESTION
          adv
          then_branch = parse_expr(0)
          eat(T::COLON)
          else_branch = parse_expr(0)
          {k: :ternary, cond: left, then: then_branch, else: else_branch}
        when T::DOT
          adv
          field_tok = cur
          field = case field_tok.type
                  when T::IDENT, T::TYPE, T::STR, T::NUM then adv; field_tok.value.to_s
                  when T::STATE_VAR then adv; field_tok.value.sub(/\A\$/, "")
                  else adv; "?"
                  end
          {k: :member, obj: left, field: field}
        when T::LBRACK
          adv
          index = parse_expr(0)
          eat(T::RBRACK)
          {k: :index, obj: left, index: index}
        else
          left
        end
      end

      def parse_comp
        name = cur.value
        adv
        eat(T::LPAREN)
        args = []
        while cur.type != T::RPAREN && cur.type != T::EOF
          args << parse_expr(0)
          adv if cur.type == T::COMMA
        end
        eat(T::RPAREN)
        {k: :comp, name: name, args: args}
      end

      def parse_arr
        adv
        els = []
        while cur.type != T::RBRACK && cur.type != T::EOF
          els << parse_expr(0)
          adv if cur.type == T::COMMA
        end
        eat(T::RBRACK)
        {k: :arr, els: els}
      end

      def parse_obj
        adv
        entries = []
        while cur.type != T::RBRACE && cur.type != T::EOF
          kt = cur
          key = case kt.type
                when T::IDENT, T::STR, T::TYPE, T::NUM then adv; kt.value.to_s
                when T::STATE_VAR then adv; kt.value.sub(/\A\$/, "")
                else adv; "?"
                end
          eat(T::COLON)
          entries << [key, parse_expr(0)]
          adv if cur.type == T::COMMA
        end
        eat(T::RBRACE)
        {k: :obj, entries: entries}
      end
    end
  end
end
