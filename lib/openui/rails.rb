# frozen_string_literal: true

require "rails/engine"
require_relative "../openui"
require_relative "rails/renderer"
require_relative "rails/progressive"
require_relative "rails/sse"
require_relative "rails/helper"
require_relative "rails/starter_library"
require_relative "rails/catalog_library"
require_relative "rails/catalog"
require_relative "rails/engine"

module OpenUI
  # Rails integration: server-side ERB rendering of OpenUI Lang, progressive
  # Turbo Stream updates, view helpers and the starter component library.
  module Rails
    autoload :CatalogController, File.expand_path("rails/catalog_controller", __dir__)

    class << self
      # The application's default library. Set it in an initializer:
      #   OpenUI::Rails.library = OpenUI::Rails::StarterLibrary.build
      # or give a callable to resolve it lazily (reloadable app code).
      attr_writer :library

      # Render unresolved references as skeleton nodes while streaming. Off by
      # default: language.md 4 rule 5 says a client shows no placeholders.
      attr_accessor :placeholders

      # Serve the component catalog at the engine's /catalog route. Off by
      # default; turn it on in development or behind your own auth.
      attr_accessor :catalog

      def library
        lib = @library
        lib = lib.call if lib.respond_to?(:call)
        lib || StarterLibrary.build
      end

      def configure
        yield self
      end
    end

    self.placeholders = false
    self.catalog = false
  end
end
