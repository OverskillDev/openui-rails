# frozen_string_literal: true

module OpenUI
  module Lang
    # One lexical token. +type+ is a Symbol; +value+ carries the payload for
    # :str, :num, :ident, :type, :state_var and :builtin_call tokens.
    Token = Struct.new(:type, :value) do
      def to_s
        value.nil? ? type.to_s : "#{type}(#{value.inspect})"
      end
    end

    # Token types, mirroring the reference lexer (packages/lang-core/src/parser/tokens.ts).
    module T
      NEWLINE = :newline
      LPAREN = :lparen
      RPAREN = :rparen
      LBRACK = :lbrack
      RBRACK = :rbrack
      LBRACE = :lbrace
      RBRACE = :rbrace
      COMMA = :comma
      COLON = :colon
      EQUALS = :equals
      TRUE = :true
      FALSE = :false
      NULL = :null
      EOF = :eof
      STR = :str
      NUM = :num
      IDENT = :ident          # lowercase identifier: a reference
      TYPE = :type            # PascalCase identifier: component name or reference
      STATE_VAR = :state_var  # $name
      DOT = :dot
      PLUS = :plus
      MINUS = :minus
      STAR = :star
      SLASH = :slash
      PERCENT = :percent
      EQEQ = :eqeq
      NOTEQ = :noteq
      GT = :gt
      LT = :lt
      GTE = :gte
      LTE = :lte
      AND = :and
      OR = :or
      NOT = :not
      QUESTION = :question
      BUILTIN_CALL = :builtin_call # @Name

      # Tokens after which a "-" is subtraction rather than a negative number (spec 1.3).
      VALUE_TOKENS = [NUM, STR, IDENT, TYPE, RPAREN, RBRACK, TRUE, FALSE, NULL, STATE_VAR, BUILTIN_CALL].freeze
    end
  end
end
