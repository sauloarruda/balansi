Rails.application.routes.draw do
  get "home/index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Auth routes
  get "/auth/callback", to: "auth/callbacks#show"
  get "/auth/sign_up", to: "auth/sessions#new"
  get "/auth/sign_in", to: "auth/sessions#new", as: :auth_login_path
  delete "/auth/sign_out", to: "auth/sessions#destroy"

  # Journal routes
  resources :journals, param: :date, constraints: { date: /\d{4}-\d{2}-\d{2}/ }, only: [ :index, :show ] do
    member do
      get :close
      patch :close
    end

    resources :meals, controller: "journal/meals", except: [ :index ]
    resources :exercises, controller: "journal/exercises", except: [ :index ]
  end

  # Defines the root path route ("/")
  root "home#index"
end
