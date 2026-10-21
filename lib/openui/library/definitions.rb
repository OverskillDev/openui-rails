# frozen_string_literal: true

module OpenUI
  class Library
    # One positional argument of a component, or one parameter of a function or action.
    Param = Struct.new(:name, :type, :required, :default, :bindable, :description, keyword_init: true) do
      def optional?
        !required
      end

      def to_json_schema(library)
        s = type.to_json_schema(library)
        s = s.merge("default" => default) unless default.nil?
        s
      end

      # A prop with a default counts as optional in the signature (prompt.md 3.1).
      def optional_in_signature?
        !required || !default.nil?
      end

      def signature(library)
        t = type.signature(library)
        t = "$binding<#{t}>" if bindable
        "#{name}#{optional_in_signature? ? "?" : ""}: #{t}"
      end
    end

    # A component the model may call. +renders+ names the partial (or any
    # callable / ViewComponent class the host's renderer understands).
    Component = Struct.new(:name, :description, :params, :renders, :signature_override, keyword_init: true) do
      def param(name)
        params.find { |p| p.name == name.to_s }
      end

      def required_params
        params.select(&:required)
      end

      def signature(library)
        signature_override || "#{name}(#{params.map { |p| p.signature(library) }.join(", ")})"
      end

      def to_json_schema(library)
        {
          "type" => "object",
          "description" => description,
          "properties" => params.to_h { |p| [p.name, p.to_json_schema(library)] },
          "required" => required_params.map(&:name)
        }.compact
      end

      # The names this component's slots refer to (for extend and validation).
      def slot_names(library)
        params.flat_map { |p| p.type.component_names(library) }.uniq
      end
    end

    # A pure function the model calls as @Name(args).
    Function = Struct.new(:name, :description, :params, :returns, :implementation, :signature_override, keyword_init: true) do
      def signature(library)
        return signature_override if signature_override
        sig = "#{name}(#{params.map { |p| p.signature(library) }.join(", ")})"
        returns ? "#{sig} → #{returns.signature(library)}" : sig
      end

      def to_json_schema(library)
        out = {
          "description" => description,
          "params" => {
            "type" => "object",
            "properties" => params.to_h { |p| [p.name, p.to_json_schema(library)] },
            "required" => params.select(&:required).map(&:name)
          }
        }
        out["returns"] = returns.to_json_schema(library) if returns
        out
      end
    end

    # A host-defined action the model uses as @Name(args) in an action position.
    Action = Struct.new(:name, :description, :params, :signature_override, keyword_init: true) do
      def signature(library)
        signature_override || "#{name}(#{params.map { |p| p.signature(library) }.join(", ")})"
      end

      def params_schema(library)
        {
          "type" => "object",
          "properties" => params.to_h { |p| [p.name, p.to_json_schema(library)] },
          "required" => params.select(&:required).map(&:name)
        }
      end

      def to_json_schema(library)
        {"description" => description, "params" => params_schema(library)}
      end

      # The $defs entry of a custom action: {type: "Name", params: {...}}.
      def def_schema(library)
        {
          "type" => "object",
          "properties" => {"type" => {"type" => "string", "const" => name}, "params" => params_schema(library)},
          "required" => %w[type params]
        }
      end
    end

    Group = Struct.new(:name, :components, :notes, keyword_init: true)
  end
end
