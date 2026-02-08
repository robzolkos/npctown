Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :agents, only: [ :create, :show, :index, :destroy ] do
        resource :perception, only: [ :show ]
        resource :plan, only: [ :show, :create, :update ]
        resources :actions, only: [ :create ]
        resources :memories, only: [ :index ]
        resources :reflections, only: [ :index ]
        resources :relationships, only: [ :index ]
      end
    end
  end

  get "docs", to: "pages#docs"
  root "pages#home"
end
