# frozen_string_literal: true

require "json"
require_relative "lang"
require_relative "library/types"
require_relative "library/definitions"
require_relative "library/prompt"

module OpenUI
  # A component library: what the model may generate (prompt.md section 2),
  # how each component renders, and the system prompt derived from it.
  #
  #   library = OpenUI::Library.define(id: "support", version: "1.0.0", root: "Stack") do
  #     component "Stack", description: "Lays out children", renders: "openui/components/stack" do
  #       arg :children, list(component)
  #       arg :direction, enum("column", "row"), optional: true
  #     end
  #   end
  #
  #   library.prompt            # the system prompt text
  #   library.schema            # the compiled OpenUI::Lang::Schema for parsing
  #   OpenUI::Lang.parse(text, library: library)
  class Library
    attr_reader :id, :version, :root, :components, :functions, :actions, :groups

    def self.define(id: nil, version: nil, root: nil, &block)
      builder = Builder.new
      builder.instance_eval(&block) if block
      new(id: id, version: version, root: root, components: builder.components, functions: builder.functions,
        actions: builder.actions, groups: builder.groups)
    end

    # Build a library from a LibrarySpec document (prompt.md section 2), as
    # written by this gem's #to_spec or the reference CLI (`openui generate --spec`).
    # Library functions have no implementation in the spec; add them with #implement.
    def self.from_spec(spec)
      spec = JSON.parse(spec) if spec.is_a?(String)
      Spec.read(spec)
    end

    # @param strict [Boolean] enforce the authoring rules of prompt.md 3.1
    #   (required before optional). Off for specs authored elsewhere.
    def initialize(id:, version:, root:, components:, functions: {}, actions: {}, groups: [], strict: true)
      @id = id
      @version = version
      @root = root
      @components = components
      @functions = functions
      @actions = actions
      @groups = groups
      validate!(strict: strict)
    end

    def component(name)
      components[name.to_s]
    end

    def component?(name)
      components.key?(name.to_s)
    end

    def function(name)
      functions[name.to_s]
    end

    def action(name)
      actions[name.to_s]
    end

    def action_name?(name)
      %w[OpenUrl ToAssistant].include?(name) || actions.key?(name)
    end

    def component_names
      components.keys
    end

    # Supply the Ruby implementation of a function declared in a spec.
    def implement(name, &block)
      fn = functions.fetch(name.to_s) { raise Lang::LibraryError, "no function named #{name}" }
      fn.implementation = block
      self
    end

    def function_implementations
      functions.transform_values(&:implementation).compact
    end

    # ── Spec output ────────────────────────────────────────────────────────

    def to_json_schema
      Spec.json_schema(self)
    end

    def to_spec
      Spec.write(self)
    end

    # The compiled schema the parser uses (memoized; libraries are immutable).
    def schema
      @schema ||= Lang::Schema.new(to_json_schema, root: root,
        bindable: components.transform_values { |c| c.params.select(&:bindable).map(&:name) })
    end

    # The system prompt (prompt.md section 4). Options as in the reference
    # PromptOptions, snake_case: preamble:, additional_rules:, examples:,
    # tool_examples:, tools:, tool_calls:, bindings:, builtin_functions:,
    # edit_mode:, inline_mode:.
    def prompt(**options)
      Prompt.generate(to_spec, options)
    end

    def parser(limits: Lang::Limits.default, placeholders: false)
      Lang.parser_for(self, limits: limits, placeholders: placeholders)
    end

    def stream_parser(limits: Lang::Limits.default, placeholders: false)
      Lang.stream_parser_for(self, limits: limits, placeholders: placeholders)
    end

    # @param complete [Boolean] false while more text is expected (keeps
    #   placeholders when placeholders: true)
    def parse(text, limits: Lang::Limits.default, placeholders: false, complete: true)
      parser(limits: limits, placeholders: placeholders).parse(text, complete: complete)
    end

    # Derive a new library (prompt.md 2.8). The base is unchanged. The derived
    # library does not inherit the base's id or version; pass id: and version:
    # to name it.
    #
    #   shop = base.extend do
    #     component "ProductCard", description: "...", renders: "...", slots: ["Card.children"] do ... end
    #     override "Text", description: "...", renders: "..." do ... end
    #     remove "Chart"
    #     function "Percent", ... do ... end
    #   end
    def extend(id: nil, version: nil, &block)
      ext = Extension.new(self, id: id, version: version)
      ext.instance_eval(&block) if block
      ext.build
    end

    private

    def validate!(strict: true)
      names = {}
      claim = lambda do |kind, name|
        raise Lang::LibraryError, "#{kind} \"#{name}\" must start with an uppercase letter" unless name.match?(/\A[A-Z][A-Za-z0-9_]*\z/)
        if Lang::Builtins::RESERVED_NAMES.include?(name)
          raise Lang::LibraryError, "#{kind} \"#{name}\" collides with a reserved name (#{Lang::Builtins::RESERVED_NAMES.join(", ")})"
        end
        raise Lang::LibraryError, "#{kind} \"#{name}\" collides with a #{names[name]} of the same name" if names.key?(name)
        names[name] = kind.downcase
      end
      components.each_key { |n| claim.call("Component", n) }
      functions.each_key { |n| claim.call("Function", n) }
      actions.each_key { |n| claim.call("Action", n) }
      if root && !components.key?(root)
        raise Lang::LibraryError, "root component \"#{root}\" is not in the library (#{components.keys.join(", ")})"
      end
      components.each_value do |c|
        if strict
          seen_optional = false
          c.params.each do |p|
            seen_optional = true if p.optional? || !p.default.nil?
            if seen_optional && p.required && p.default.nil?
              raise Lang::LibraryError, "#{c.name}: required argument \"#{p.name}\" must come before optional ones"
            end
          end
        end
        c.slot_names(self).each do |n|
          raise Lang::LibraryError, "#{c.name} refers to unknown component \"#{n}\"" unless components.key?(n)
        end
        c.params.each do |p|
          next unless p.type.is_a?(Types::ActionSlot) || (p.type.is_a?(Types::Optional) && p.type.inner.is_a?(Types::ActionSlot))
          p.type.inner.names.each do |n|
            raise Lang::LibraryError, "#{c.name}.#{p.name} refers to unknown action \"#{n}\"" unless action_name?(n)
          end
        end
      end
      groups.each do |g|
        g.components.each do |n|
          raise Lang::LibraryError, "group \"#{g.name}\" lists unknown component \"#{n}\"" unless components.key?(n)
        end
      end
    end

    # ── DSL ────────────────────────────────────────────────────────────────

    # Type helpers shared by component, function and action blocks.
    module TypeDSL
      def string = Types::Scalar.new(:string)
      def number = Types::Scalar.new(:number)
      def boolean = Types::Scalar.new(:boolean)
      def any = Types::Scalar.new(:any)
      def enum(*values) = Types::Enum.new(values.flatten)
      def list(of) = Types::List.new(coerce(of))
      def object(**fields) = Types::ObjectType.new(fields.transform_values { |t| coerce(t) })
      def optional(type) = coerce(type).optional
      def component(*names) = Types::Slot.new(names.flatten)
      def action = Types::ActionSlot.new([])
      def actions(*names) = Types::ActionSlot.new(names.flatten)

      def coerce(type)
        case type
        when Types::Base then type
        when Symbol then Types::Scalar.new(type)
        when Array then Types::List.new(coerce(type.first))
        else raise Lang::LibraryError, "unknown argument type #{type.inspect}"
        end
      end
    end

    class ParamsBuilder
      include TypeDSL
      attr_reader :params

      def initialize
        @params = []
      end

      # @param required [Boolean, nil] defaults to true unless optional: true or a default is given
      def arg(name, type, required: nil, optional: nil, default: nil, description: nil, binding: false)
        type = coerce(type)
        required = !(optional || type.optional? || !default.nil?) if required.nil?
        name = name.to_s
        raise Lang::LibraryError, "argument \"#{name}\" must be a valid identifier" unless name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
        raise Lang::LibraryError, "duplicate argument \"#{name}\"" if @params.any? { |p| p.name == name }
        @params << Param.new(name: name, type: type.inner, required: required, default: default,
          bindable: binding, description: description)
      end
      alias_method :param, :arg
    end

    class ComponentBuilder < ParamsBuilder
      def initialize(name, description:, renders:)
        super()
        @name = name.to_s
        @description = description
        @renders = renders
      end

      def description(text = nil)
        return @description if text.nil?
        @description = text
      end

      def renders(value = nil)
        return @renders if value.nil?
        @renders = value
      end

      def build
        raise Lang::LibraryError, "component \"#{@name}\" needs a description" if @description.to_s.empty?
        Component.new(name: @name, description: @description, params: params, renders: @renders)
      end
    end

    class FunctionBuilder < ParamsBuilder
      def initialize(name, description:, returns:)
        super()
        @name = name.to_s
        @description = description
        @returns = returns ? coerce(returns) : nil
        @implementation = nil
      end

      def implement(&block)
        @implementation = block
      end

      def build
        Function.new(name: @name, description: @description, params: params, returns: @returns, implementation: @implementation)
      end
    end

    class ActionBuilder < ParamsBuilder
      def initialize(name, description:)
        super()
        @name = name.to_s
        @description = description
      end

      def build
        Action.new(name: @name, description: @description, params: params)
      end
    end

    class Builder
      include TypeDSL
      attr_reader :components, :functions, :actions, :groups

      def initialize
        @components = {}
        @functions = {}
        @actions = {}
        @groups = []
      end

      def component(name, description: nil, renders: nil, &block)
        b = ComponentBuilder.new(name, description: description, renders: renders)
        b.instance_eval(&block) if block
        c = b.build
        raise Lang::LibraryError, "component \"#{c.name}\" is defined twice" if @components.key?(c.name)
        @components[c.name] = c
      end

      def function(name, description:, returns: nil, &block)
        b = FunctionBuilder.new(name, description: description, returns: returns)
        b.instance_eval(&block) if block
        f = b.build
        @functions[f.name] = f
      end

      def action(name, description:, &block)
        b = ActionBuilder.new(name, description: description)
        b.instance_eval(&block) if block
        a = b.build
        @actions[a.name] = a
      end

      def group(name, components:, notes: [])
        @groups << Group.new(name: name, components: components.map(&:to_s), notes: notes)
      end
    end

    # library.extend { ... } verbs.
    class Extension < Builder
      def initialize(base, id: nil, version: nil)
        super()
        @base = base
        @id = id
        @version = version
        @components = base.components.dup
        @functions = base.functions.dup
        @actions = base.actions.dup
        @groups = base.groups.map(&:dup)
        @slot_requests = {}
        @removed = []
      end

      # Add a component. +slots+ names parents ("Card.children", or "Card" when
      # the parent has one component slot) whose unions gain the new component.
      def component(name, description: nil, renders: nil, slots: nil, &block)
        raise Lang::LibraryError, "Component \"#{name}\" already exists. Use override." if @components.key?(name.to_s)
        c = super(name, description: description, renders: renders, &block)
        @slot_requests[c.name] = slots if slots
        c
      end

      def override(name, description: nil, renders: nil, &block)
        raise Lang::LibraryError, "Cannot override \"#{name}\": not in the library. Use component." unless @components.key?(name.to_s)
        b = ComponentBuilder.new(name, description: description, renders: renders)
        b.instance_eval(&block) if block
        @components[name.to_s] = b.build
      end

      def remove(name)
        name = name.to_s
        raise Lang::LibraryError, "Cannot remove \"#{name}\": not in the library." unless @components.key?(name)
        raise Lang::LibraryError, "Cannot remove \"#{name}\": it is the library root." if name == @base.root
        @components.delete(name)
        @removed << name
      end

      def build
        @slot_requests.each do |new_name, slots|
          slots.each do |slot|
            parent_name, prop = slot.to_s.split(".", 2)
            parent = @components[parent_name] or raise Lang::LibraryError, "Slot \"#{slot}\" for \"#{new_name}\": \"#{parent_name}\" is not in the library."
            candidates = parent.params.select { |p| slot_type(p.type) }
            param = if prop
              candidates.find { |p| p.name == prop }
            elsif candidates.length == 1
              candidates.first
            end
            raise Lang::LibraryError, "Slot \"#{slot}\" for \"#{new_name}\" must be one content slot. Candidates: #{candidates.map { |p| "#{parent_name}.#{p.name}" }.join(", ")}." unless param
            add_to_slot(param, new_name)
          end
        end
        @removed.each do |gone|
          @components.each_value do |c|
            c.params.each do |p|
              slot = slot_type(p.type)
              next unless slot && !slot.any? && slot.names.include?(gone)
              remaining = slot.names - [gone]
              raise Lang::LibraryError, "Cannot remove \"#{gone}\": it is the only type allowed in #{c.name}.#{p.name}." if remaining.empty?
              replace_slot(p, Types::Slot.new(remaining))
            end
          end
          @groups.each { |g| g.components -= [gone] }
        end
        @groups.reject! { |g| g.components.empty? }
        Library.new(id: @id, version: @version, root: @base.root, components: @components, functions: @functions,
          actions: @actions, groups: @groups)
      end

      private

      def slot_type(type)
        inner = type.inner
        return inner if inner.is_a?(Types::Slot)
        return inner.of.inner if inner.is_a?(Types::List) && inner.of.inner.is_a?(Types::Slot)
        nil
      end

      def add_to_slot(param, name)
        slot = slot_type(param.type)
        return if slot.any? || slot.names.include?(name)
        replace_slot(param, Types::Slot.new(slot.names + [name]))
      end

      def replace_slot(param, new_slot)
        inner = param.type.inner
        param.type = if inner.is_a?(Types::List)
          Types::List.new(new_slot)
        else
          new_slot
        end
      end
    end

    # LibrarySpec reader and writer (prompt.md section 2).
    module Spec
      module_function

      def json_schema(library)
        defs = {}
        library.components.each_value { |c| defs[c.name] = c.to_json_schema(library) }
        Lang::Builtins.action_defs.each { |k, v| defs[k] = v unless defs.key?(k) }
        library.actions.each_value { |a| defs[a.name] = a.def_schema(library) unless defs.key?(a.name) }
        out = {
          "type" => "object",
          "properties" => library.components.keys.to_h { |n| [n, {"$ref" => "#/$defs/#{n}"}] },
          "required" => library.components.keys,
          "additionalProperties" => false,
          "$defs" => defs
        }
        out["functions"] = library.functions.transform_values { |f| f.to_json_schema(library) } unless library.functions.empty?
        out["actions"] = library.actions.transform_values { |a| a.to_json_schema(library) } unless library.actions.empty?
        out
      end

      def write(library)
        spec = {}
        spec["id"] = library.id if library.id
        spec["version"] = library.version if library.version
        spec["root"] = library.root if library.root
        spec["schema"] = json_schema(library)
        spec["components"] = library.components.transform_values do |c|
          {"signature" => c.signature(library), "description" => c.description}
        end
        unless library.groups.empty?
          spec["componentGroups"] = library.groups.map do |g|
            h = {"name" => g.name, "components" => g.components}
            h["notes"] = g.notes unless g.notes.nil? || g.notes.empty?
            h
          end
        end
        unless library.functions.empty?
          spec["functions"] = library.functions.transform_values { |f| {"signature" => f.signature(library), "description" => f.description} }
        end
        unless library.actions.empty?
          spec["actions"] = library.actions.transform_values { |a| {"signature" => a.signature(library), "description" => a.description} }
        end
        spec
      end

      def read(spec)
        schema = spec["schema"] || {}
        defs = schema["$defs"] || {}
        names = (schema["properties"] || defs).keys
        action_names = (schema["actions"] || {}).keys
        reserved_defs = Lang::Builtins.action_defs.keys + action_names
        components = {}
        names.each do |name|
          d = defs[name]
          next unless d
          next if reserved_defs.include?(name) && !(schema["properties"] || {}).key?(name)
          meta = (spec["components"] || {})[name] || {}
          bindable = meta["signature"].to_s.scan(/(\w+)\??: \$binding</).flatten
          components[name] = Component.new(
            name: name,
            description: meta["description"] || d["description"] || "",
            params: read_params(d, bindable),
            renders: nil,
            signature_override: meta["signature"]
          )
        end
        functions = (schema["functions"] || {}).to_h do |name, f|
          meta = (spec["functions"] || {})[name] || {}
          [name, Function.new(name: name, description: f["description"] || meta["description"], params: read_params(f["params"] || {}, []),
            returns: f["returns"] ? Types::FromSchema.new(f["returns"]) : nil, implementation: nil,
            signature_override: meta["signature"])]
        end
        actions = (schema["actions"] || {}).to_h do |name, a|
          meta = (spec["actions"] || {})[name] || {}
          [name, Action.new(name: name, description: a["description"] || meta["description"], params: read_params(a["params"] || {}, []),
            signature_override: meta["signature"])]
        end
        groups = (spec["componentGroups"] || []).map { |g| Group.new(name: g["name"], components: g["components"] || [], notes: g["notes"] || []) }
        Library.new(id: spec["id"], version: spec["version"], root: spec["root"], components: components,
          functions: functions, actions: actions, groups: groups, strict: false)
      end

      def read_params(d, bindable)
        props = d["properties"] || {}
        required = d["required"] || []
        props.map do |name, fragment|
          Param.new(name: name, type: Types::FromSchema.new(fragment.reject { |k, _| k == "default" }), required: required.include?(name),
            default: fragment.is_a?(Hash) ? fragment["default"] : nil, bindable: bindable.include?(name))
        end
      end
    end
  end
end
