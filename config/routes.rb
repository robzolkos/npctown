Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :agents, only: [ :create, :show, :index, :destroy ] do
        resource :perception, only: [ :show ]
        resources :actions, only: [ :create ]
        resources :memories, only: [ :index ]
      end
    end
  end

  get "docs", to: "pages#docs"
  root "pages#home"
end
