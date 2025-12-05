defmodule JournalWeb.Router do
  use JournalWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Routes without /api prefix - API Gateway handles path routing
  scope "/", JournalWeb do
    pipe_through :api

    # Health check
    get "/health", HealthController, :index

    # Meal endpoints (patient_id will come from Bearer token, using constant for POC)
    get "/meals", MealController, :index
    post "/meals", MealController, :create
    get "/meals/:id", MealController, :show
    post "/meals/:id/confirm", MealController, :confirm
  end
end
