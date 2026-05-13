Rails.application.routes.draw do # rubocop:disable Metrics/BlockLength
  match "/403", to: "errors#forbidden", via: :all
  match "/404", to: "errors#not_found", via: :all
  match "/500", to: "errors#internal_server_error", via: :all

  direct(:auth_sign_up) { "/auth/sign_up" }
  direct(:auth_login) { "/auth/sign_in" }
  direct(:auth_sign_out) { "/auth/sign_out" }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  scope module: :users, path: "user", as: :user do
    resource :profile, only: [ :show, :update ]
  end

  scope module: :patients, path: "patient", as: :patient do
    resource :personal_profile, only: [ :show, :update ]
    resource :clinical_assessment, only: [ :show, :update ]
    resources :professional_accesses, only: [ :index, :create, :destroy ]
    resources :recipes do
      collection do
        get :search, to: "recipes/search#index"
      end

      resources :images, only: [ :destroy ], controller: "recipe_images"
    end
  end

  scope path: "professional", module: "professionals", as: "professional" do
    resources :patients, only: [ :index, :show ] do
      member do
        get :journal, to: "patients/journals#show"
        get :journal_today, to: "patients/journals#today"
      end
      resource :personal_profile, only: [ :edit, :update ], controller: "patients/personal_profiles"
      resource :clinical_assessment, only: [ :edit, :update ], controller: "patients/clinical_assessments"
    end
  end

  # Journal routes
  resources :journals, param: :date, constraints: { date: /\d{4}-\d{2}-\d{2}/ }, only: [ :index, :show ] do
    collection do
      get :today
    end

    member do
      get :close
      patch :close
    end

    resources :meals, controller: "journal_entries/meals", except: [ :index ]
    resources :exercises, controller: "journal_entries/exercises", except: [ :index ]
  end

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Public invite entry point — must be declared LAST to avoid shadowing other routes
  get "/:invite_code", to: "invites#show", as: :invite_signup,
      constraints: { invite_code: /[A-Za-z0-9]{6}/ }

  # Defines the root path route ("/")
  root to: redirect { |params, request| "/journals/today#{request.query_string.present? ? "?#{request.query_string}" : ""}" }
end
