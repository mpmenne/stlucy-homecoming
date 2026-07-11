Rails.application.routes.draw do
  get "/healthz", to: proc { [200, { "Content-Type" => "text/plain" }, ["ok"]] }

  namespace :api do
    resources :slots, only: :index
    resources :signups, only: :create
    resources :chairs, only: :create
    resource :crew, only: :create, controller: "crew"
  end
end
