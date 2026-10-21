# frozen_string_literal: true

module OpenUI
  module Rails
    # Adds the gem's component partials and stylesheet to the host's view and
    # asset paths, mixes the view helpers in, and wires the RubyLLM hook when
    # RubyLLM is loaded. A host overrides a starter partial by creating the
    # same path under its own app/views.
    class Engine < ::Rails::Engine
      engine_name "openui"

      initializer "openui.helpers" do
        ActiveSupport.on_load(:action_view) { include OpenUI::Rails::Helper }
      end

      initializer "openui.assets" do |app|
        if app.config.respond_to?(:assets)
          app.config.assets.paths << root.join("app/assets/stylesheets").to_s
          app.config.assets.precompile += %w[openui.css] if app.config.assets.respond_to?(:precompile)
        end
      end

      config.after_initialize do
        if defined?(::RubyLLM::Chat)
          require "openui/ruby_llm"
          OpenUI::RubyLLM.install!
        end
      end
    end
  end
end
