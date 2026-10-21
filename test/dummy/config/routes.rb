# frozen_string_literal: true

Rails.application.routes.draw do
  root "demo#index"
  get "demo", to: "demo#index"
  post "demo", to: "demo#create"
  get "demo/:id", to: "demo#show", as: :demo_run
  get "demo/:id/events", to: "demo#events", as: :demo_events
  get "sample", to: "demo#sample", as: :sample
  get "catalog", to: OpenUI::Rails::CatalogController.action(:index), as: :catalog
  mount OpenUI::Rails::Engine, at: "/openui"
end
