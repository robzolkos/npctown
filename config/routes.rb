Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :agents, only: [ :create, :show, :index, :destroy ]
    end
  end

  root "pages#home"
end
