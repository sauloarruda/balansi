defmodule JournalWeb.Router do
  use JournalWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Health check at root (for Lambda Web Adapter readiness check)
  scope "/", JournalWeb do
    pipe_through :api
    get "/health", HealthController, :index
  end

  # API routes with /journal prefix (API Gateway path)
  scope "/journal", JournalWeb do
    pipe_through :api

    # Health check
    get "/health", HealthController, :index

    # Auth endpoints
    get "/auth/callback", AuthController, :callback
    # post "/auth/refresh", AuthController, :refresh  # To be implemented in Phase 6

    # Meal endpoints (patient_id will come from Bearer token, using constant for POC)
    get "/meals", MealController, :index
    post "/meals", MealController, :create
    get "/meals/:id", MealController, :show
    post "/meals/:id/confirm", MealController, :confirm
  end
end
