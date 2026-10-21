# frozen_string_literal: true

module OpenUI
  module Rails
    # Serves the component catalog (GET /openui/catalog when the engine is
    # mounted). Off unless OpenUI::Rails.catalog is true. Loaded on first use
    # (autoload) so requiring the gem does not load ActionController early.
    class CatalogController < ::ActionController::Base
      def index
        return head(:not_found) unless OpenUI::Rails.catalog
        @theme = params[:theme] if %w[light dark].include?(params[:theme])
        render template: "openui/catalog/index", layout: "openui/catalog"
      end
    end
  end
end
