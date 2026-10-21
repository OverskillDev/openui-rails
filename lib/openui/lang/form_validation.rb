# frozen_string_literal: true

module OpenUI
  module Lang
    # Validation rules for input components (language.md 5.4). openui-rails
    # v0.1 ships no form components; this is here so hosts that add them get
    # the spec's rules, and for the state/*-validation-* conformance case.
    # Ported from utils/validation.ts (MIT).
    module FormValidation
      EMAIL = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
      NUMERIC_RULES = %w[min max minLength maxLength].freeze

      module_function

      def empty?(value)
        return true if value.nil? || value == ""
        return true if value.is_a?(Array) && value.empty?
        if value.is_a?(Hash)
          return empty?(value["value"]) if value.key?("value")
          return true if value.empty?
        end
        false
      end

      def parse_float(value)
        m = value.to_s.strip.match(/\A[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/)
        m ? Float(m[0]) : nil
      end

      # @param rules [Hash] {"required" => true, "minLength" => 3, ...}
      # @return [String, nil] the first failing rule's message
      def validate(value, rules)
        rules.each do |type, arg|
          next if arg == false || arg.nil?
          message = check(type.to_s, value, arg)
          return message if message
        end
        nil
      end

      def valid?(value, rules)
        validate(value, rules).nil?
      end

      def check(type, value, arg)
        case type
        when "required"
          return "This field is required" if empty?(value)
          if value.is_a?(Hash)
            vals = value.values
            return "At least one option is required" if !vals.empty? && vals.all? { |v| v == true || v == false } && vals.none?
          end
          nil
        when "email"
          return nil if empty?(value)
          (value.is_a?(String) && EMAIL.match?(value)) ? nil : "Please enter a valid email"
        when "url"
          return nil if empty?(value)
          return "Please enter a valid URL" unless value.is_a?(String)
          uri = begin
            URI.parse(value)
          rescue URI::InvalidURIError
            nil
          end
          (uri && uri.scheme && uri.host) ? nil : "Please enter a valid URL"
        when "numeric"
          return nil if empty?(value)
          return nil if value.is_a?(Numeric) && !(value.is_a?(Float) && value.nan?)
          return nil if value.is_a?(String) && !value.strip.empty? && !parse_float(value).nil?
          "Must be a number"
        when "min", "max"
          return nil if empty?(value)
          n = value.is_a?(Numeric) ? value : parse_float(value.to_s)
          return nil if n.nil?
          limit = Float(arg)
          if type == "min"
            n >= limit ? nil : "Must be at least #{arg}"
          else
            n <= limit ? nil : "Must be no more than #{arg}"
          end
        when "minLength", "maxLength"
          return nil if empty?(value) || !value.is_a?(String)
          limit = Integer(arg)
          if type == "minLength"
            value.length >= limit ? nil : "Must be at least #{arg} characters"
          else
            value.length <= limit ? nil : "Must be no more than #{arg} characters"
          end
        when "pattern"
          return nil if empty?(value) || !value.is_a?(String) || !arg.is_a?(String)
          begin
            Regexp.new(arg).match?(value) ? nil : "Invalid format"
          rescue RegexpError
            nil
          end
        end
      end
    end
  end
end
