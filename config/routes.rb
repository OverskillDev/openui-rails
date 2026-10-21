# frozen_string_literal: true

# Engine routes. A host mounts them with
#   mount OpenUI::Rails::Engine, at: "/openui"
# and turns the catalog on with OpenUI::Rails.catalog = true.
OpenUI::Rails::Engine.routes.draw do
  get "catalog", to: OpenUI::Rails::CatalogController.action(:index), as: :catalog
end
