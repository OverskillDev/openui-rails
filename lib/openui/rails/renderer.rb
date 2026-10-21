# frozen_string_literal: true

require "erb"
require "json"

module OpenUI
  module Rails
    # Renders a parsed OpenUI Lang tree to HTML with the host's partials.
    #
    # Only components registered in the library are instantiated; the parser
    # has already dropped anything else. Every value reaches the page through
    # ERB escaping or +text+; the renderer never marks model text html_safe.
    # A partial that raises is contained (language.md 8.2 render-error): the
    # node renders as an empty marked element and the error is recorded.
    class Renderer
      Trace = Struct.new(:html, :children, keyword_init: true)

      attr_reader :library, :view_context, :mount_id, :errors, :trace

      # @param library [OpenUI::Library]
      # @param view_context [ActionView::Base] where partials render; defaults to a plain controller view
      # @param mount_id [String] DOM id prefix for statement-bound nodes ("#{mount_id}-#{statement}")
      # @param placeholders [Boolean] render Placeholder values as skeleton nodes
      def initialize(library, view_context: nil, mount_id: "openui", placeholders: OpenUI::Rails.placeholders)
        @library = library
        @view_context = view_context || self.class.default_view_context
        @mount_id = mount_id
        @placeholders = placeholders
        @errors = []
        @trace = {}
        @stack = []
      end

      def self.default_view_context
        ::ActionController::Base.new.view_context
      end

      def dom_id(statement_id)
        "#{mount_id}-#{statement_id.to_s.gsub(/[^A-Za-z0-9_$-]/, "_")}"
      end

      # Render a ParseResult, an Element, or any node value. Returns html_safe HTML.
      def render(value)
        @errors = []
        @trace = {}
        value = value.root if value.is_a?(Lang::ParseResult)
        node(value)
      end

      # Render any value in a component position: elements, arrays of them,
      # placeholders, or text (language.md 3.2: scalars render as text).
      def node(value)
        case value
        when nil then safe("")
        when Lang::Element then element(value)
        when Lang::Placeholder then placeholder(value)
        when Array then safe(value.map { |v| node(v) }.join)
        when Lang::Dynamic then node(value.value)
        when Lang::ActionPlan, Lang::Binding then safe("")
        else safe(ERB::Util.html_escape(text(value)))
        end
      end

      # Display text for a scalar or data value; the caller's ERB escapes it.
      def text(value)
        case value
        when nil then ""
        when String then value
        when Numeric, true, false then Lang::Builtins.js_string(value)
        when Lang::Dynamic then text(value.value)
        when Lang::Element then ""
        when Array, Hash then JSON.generate(strip(value))
        else value.to_s
        end
      end

      private

      def safe(html)
        html.html_safe # rubocop:disable Rails/OutputSafety -- built from escaped parts and partial output
      end

      def strip(value)
        case value
        when Array then value.map { |v| strip(v) }
        when Hash then value.transform_values { |v| strip(v) }
        when Lang::Element then value.to_h
        when Lang::Dynamic then strip(value.value)
        when Lang::Placeholder, Lang::ActionPlan, Lang::Binding then nil
        else value
        end
      end

      def element(el)
        component = library.component(el.type)
        return safe("") unless component
        sid = el.statement_id
        @stack.last[:children] << sid if sid && @stack.last
        @stack.push({id: sid, children: []}) if sid
        inner = begin
          render_component(component, el)
        rescue StandardError => e
          @errors << Lang::Error.new(source: "runtime", code: "render-error", component: el.type, statement_id: sid,
            message: "#{e.class}: #{e.message}")
          ::Rails.logger&.warn("[openui] render-error in #{el.type}: #{e.class}: #{e.message}")
          %(<div class="openui-render-error" data-openui-component="#{ERB::Util.html_escape(el.type)}"></div>)
        end
        if sid
          frame = @stack.pop
          html = wrap(sid, inner)
          @trace[sid] = Trace.new(html: html, children: frame[:children])
          safe(html)
        else
          safe(inner)
        end
      end

      def wrap(sid, inner, extra_class: nil, extra_attrs: "")
        id = ERB::Util.html_escape(dom_id(sid))
        klass = ["openui-node", extra_class].compact.join(" ")
        %(<div id="#{id}" class="#{klass}" data-openui-statement="#{ERB::Util.html_escape(sid)}"#{extra_attrs}>#{inner}</div>)
      end

      def placeholder(ph)
        return safe("") unless @placeholders
        sid = ph.name
        @stack.last[:children] << sid if @stack.last
        html = wrap(sid, "", extra_class: "openui-pending", extra_attrs: ' aria-busy="true"')
        @trace[sid] = Trace.new(html: html, children: [])
        safe(html)
      end

      def render_component(component, el)
        locals = {element: el, openui: self}
        component.params.each do |param|
          value = el.props.key?(param.name) ? el.props[param.name] : param.default
          locals[param.name.to_sym] = value
        end
        target = component.renders
        case target
        when String
          view_context.render(partial: target, locals: locals)
        when Proc
          target.arity == 1 ? target.call(locals) : target.call(locals, view_context)
        when Class
          if target.method_defined?(:render_in)
            target.new(**locals.except(:element, :openui), element: el, openui: self).render_in(view_context)
          else
            raise Lang::LibraryError, "#{component.name}: renders class #{target} does not respond to render_in"
          end
        when nil
          raise Lang::LibraryError, "#{component.name}: no renderer registered (renders:)"
        else
          raise Lang::LibraryError, "#{component.name}: unsupported renders: #{target.inspect}"
        end.to_s
      end
    end
  end
end
