# frozen_string_literal: true

require "rails/generators/base"

module Openui
  # bin/rails generate openui:install
  #
  # Writes config/initializers/openui.rb and app/libraries/openui_library.rb,
  # and with --partials copies the starter component partials into the app so
  # they can be restyled.
  class InstallGenerator < ::Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)
    class_option :partials, type: :boolean, default: false, desc: "Copy the starter partials into app/views/openui/components"

    def create_initializer
      template "initializer.rb.tt", "config/initializers/openui.rb"
    end

    def create_library
      template "openui_library.rb.tt", "app/libraries/openui_library.rb"
    end

    def copy_partials
      return unless options[:partials]
      src = File.expand_path("../../../../app/views/openui/components", __dir__)
      Dir[File.join(src, "_*.html.erb")].sort.each do |path|
        copy_file path, "app/views/openui/components/#{File.basename(path)}"
      end
    end

    def show_next_steps
      say ""
      say "openui-rails is set up.", :green
      say "  1. Edit app/libraries/openui_library.rb to add or restyle components."
      say "  2. Add <%= openui_stylesheet_tag %> to your layout (or import openui.css)."
      say "  3. In a RubyLLM chat: chat.with_openui(OpenuiLibrary.instance).ask_openui(prompt)"
      say "     then render with <%= openui_render(result) %>."
    end
  end
end
