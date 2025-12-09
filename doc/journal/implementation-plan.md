# Implementation Plan — Journal Service POC (Elixir + Phoenix)

## Overview

This document outlines the implementation plan for the **Meal Logging POC** of the Balansi Journal module. The goal is to create the first endpoint `POST /meals` that creates a MealEntry with `status = pending`.

### POC Simplifications

- **No authentication:** `user_id` is obtained from a constant (will come from Bearer token in production)
- **No users table:** `user_id` is stored as a simple integer without FK constraints
- **Routes without `/api` prefix:** API Gateway handles path routing

**Tech Stack:**
- **Language:** Elixir
- **Framework:** Phoenix (API-only mode)
- **Database:** PostgreSQL (shared with auth service)
- **Deployment:** AWS Lambda (using Lambda Web Adapter)
- **Infrastructure:** Serverless Framework

---

## Phase 1: Project Setup & Configuration ✅

### 1.1 Initialize Phoenix Project ✅

**Completed:**
- [x] Created `services/journal` directory
- [x] Initialized Phoenix 1.8 project with `--no-html --no-assets --no-live --no-mailer --no-dashboard`
- [x] Configured API-only mode
- [x] Added dependencies: Phoenix 1.8, Ecto, Postgrex, Req, Corsica, Credo, ExMachina

**Commit:** `feat(journal): initialize Elixir/Phoenix service for meal logging`

---

### 1.2 Configure Application ✅

**Completed:**
- [x] Configured `config/dev.exs` with DATABASE_URL support
- [x] Configured `config/prod.exs` for Lambda (removed force_ssl)
- [x] Configured `config/runtime.exs` for environment variables
- [x] Added CORS and OpenAI config placeholders

---

### 1.3 Setup Makefile & Scripts ✅

**Completed:**
- [x] Created `Makefile` with all common commands
- [x] Created `.env.example` file
- [x] Created `README.md` with setup instructions

---

## Phase 2: Create Basic Endpoint (200 OK) ✅

### 2.1 Define Routes ✅

**Completed:**
- [x] Configured router in `lib/journal_web/router.ex`
- [x] Added `GET /health` endpoint
- [x] Added `POST /meals` and `GET /meals` endpoints

---

### 2.2 Create Controllers ✅

**Completed:**
- [x] Created `HealthController` returning service status + timestamp
- [x] Created `MealController` with stub `create` and `index` actions
- [x] Added CORS middleware to endpoint (origins: "*" for POC)

**Commit:** `feat(journal): add health and meal controllers with CORS support`

---

### 2.3 Verify Endpoint Works ✅

**Tested endpoints:**
```bash
# Health check
curl http://localhost:4000/health
# → {"status":"ok","service":"journal","timestamp":"2025-12-05T..."}

# Create meal (stub)
curl -X POST http://localhost:4000/meals \
  -H "Content-Type: application/json" \
  -d '{"meal_type":"breakfast","original_description":"2 eggs and toast"}'
# → {"data":{...},"message":"Meal created successfully (stub response)"}

# List meals (stub)
curl "http://localhost:4000/meals?date=2025-12-05"
# → {"data":[],"meta":{...},"message":"Meals list (stub response)"}

# CORS preflight
curl -I -X OPTIONS http://localhost:4000/meals -H "Origin: http://localhost:5173"
# → access-control-allow-origin: *
```

---

## Phase 3: Database & Migrations ✅

### 3.1 Create Database Migrations ✅

**Completed:**
- [x] Created migration with PostgreSQL ENUMs (`meal_type`, `entry_status`)
- [x] Created `meal_entries` table with all fields
- [x] Added indexes on `(patient_id, date)` and `status`
- [x] Ran migrations locally
- [x] Fixed `schema_migrations` table compatibility with Go auth service (added `inserted_at` column and `dirty` default)

**Tables to create:**

> **Note:** For the POC, we're not creating a patients table. The `patient_id` is a simple integer reference. In production, this will reference the users table from the auth service.

#### PostgreSQL Enums
```sql
-- Enum for meal types (4 bytes instead of VARCHAR)
CREATE TYPE meal_type AS ENUM ('breakfast', 'lunch', 'snack', 'dinner');

-- Enum for entry status (workflow: pending → processing → in_review → confirmed)
CREATE TYPE entry_status AS ENUM ('pending', 'processing', 'in_review', 'confirmed');
```

**Status workflow:**
- `pending` - Record created, waiting in queue for LLM processing
- `processing` - LLM is actively estimating nutritional values
- `in_review` - LLM finished, waiting for user to review and confirm
- `confirmed` - User confirmed, counts in daily totals

#### meal_entries
```sql
CREATE TABLE meal_entries (
  id SERIAL PRIMARY KEY,
  patient_id INTEGER NOT NULL,  -- POC: No FK constraint. Production: REFERENCES users(id)
  date DATE NOT NULL,
  meal_type meal_type NOT NULL,
  original_description TEXT NOT NULL,
  protein_g DECIMAL(10,2),
  carbs_g DECIMAL(10,2),
  fat_g DECIMAL(10,2),
  calories_kcal INTEGER,
  weight_g INTEGER,
  ai_comment TEXT,
  status entry_status NOT NULL DEFAULT 'pending',
  has_manual_override BOOLEAN DEFAULT FALSE,
  overridden_fields JSONB DEFAULT '{}',
  source_recipe_id INTEGER,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_meal_entries_patient_date ON meal_entries(patient_id, date);
CREATE INDEX idx_meal_entries_status ON meal_entries(status);
```

**Schema changes from original ERD:**
- `user_id` → `patient_id` (clearer naming for Journal context)
- `meal_type` VARCHAR → ENUM (saves disk space, enforces values)
- `status` VARCHAR → ENUM (same benefits)
- Removed `final_description` (keep only `original_description` for POC)
- `comment` → `ai_comment` (clearer naming)
- Removed `llm_raw_response` (log instead of storing - multiple interactions, mainly for debug)

**Commit:** `feat(journal): add database migration and MealEntry schema`

---

### 3.2 Create Ecto Schemas ✅

**Completed:**
- [x] Created `Journal.Meals.MealEntry` schema
- [x] Defined Ecto.Enum for meal_type and status
- [x] Created changesets: `changeset/2`, `processing_changeset/1`, `review_changeset/2`, `confirm_changeset/1`, `override_changeset/2`

**Schema:**
```elixir
# lib/journal/meals/meal_entry.ex
defmodule Journal.Meals.MealEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @meal_types [:breakfast, :lunch, :snack, :dinner]
  @statuses [:pending, :processing, :in_review, :confirmed]

  schema "meal_entries" do
    field :patient_id, :integer
    field :date, :date
    field :meal_type, Ecto.Enum, values: @meal_types
    field :original_description, :string
    field :protein_g, :decimal
    field :carbs_g, :decimal
    field :fat_g, :decimal
    field :calories_kcal, :integer
    field :weight_g, :integer
    field :ai_comment, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :has_manual_override, :boolean, default: false
    field :overridden_fields, :map, default: %{}
    field :source_recipe_id, :integer

    timestamps(type: :utc_datetime)
  end

  @required_fields [:patient_id, :date, :meal_type, :original_description]
  @optional_fields [:protein_g, :carbs_g, :fat_g, :calories_kcal, :weight_g,
                    :ai_comment, :status, :has_manual_override, :overridden_fields,
                    :source_recipe_id]

  def changeset(meal_entry, attrs) do
    meal_entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  def meal_types, do: @meal_types
  def statuses, do: @statuses
end
```

---

## Phase 4: Service Layer & Business Logic ✅

### 4.1 Create MealService ✅

**Completed:**
- [x] Created `Journal.Services.MealService` module
- [x] Implemented `create_meal/2` with date parsing
- [x] Implemented `process_with_llm/1` for full flow
- [x] Implemented status transitions: `start_processing/1`, `complete_processing/2`, `confirm_meal/1`
- [x] Implemented `override_values/2` for manual overrides
- [x] Implemented `list_meals/2` with date/status filters
- [x] Implemented `get_meal/2`

**Service interface:**
```elixir
# lib/journal/services/meal_service.ex
defmodule Journal.Services.MealService do
  alias Journal.Repo
  alias Journal.Meals.MealEntry

  @doc """
  Creates a new meal entry with pending status.
  In Phase 5, this will call LLM for macro estimation.

  patient_id: For POC, this is a constant. In production, extracted from Bearer token.
  """
  def create_meal(patient_id, attrs) do
    attrs = Map.merge(attrs, %{
      "patient_id" => patient_id,
      "status" => :pending,
      "date" => Map.get(attrs, "date", Date.utc_today())
    })

    %MealEntry{}
    |> MealEntry.changeset(attrs)
    |> Repo.insert()
  end
end
```

---

### 4.2 Create LLMService (Stub) ✅

**Completed:**
- [x] Created `Journal.Services.LLMService` module
- [x] Implemented `estimate_meal/1` with keyword-based heuristics
- [x] Returns mock nutritional data based on meal description (eggs, chicken, salad, rice, fish, etc.)

**Commit:** `feat(journal): add service layer with MealService and LLMService stub`

**Stub implementation:**
```elixir
# lib/journal/services/llm_service.ex
defmodule Journal.Services.LLMService do
  @doc """
  Estimates nutritional information for a meal description.
  TODO: Integrate with OpenAI in Phase 5
  """
  def estimate_meal(_user_profile, meal_description) do
    # Stub response for POC
    {:ok, %{
      protein_g: 25.0,
      carbs_g: 45.0,
      fat_g: 10.0,
      calories_kcal: 370,
      weight_g: 250,
      comment: "AI estimation pending integration"
    }}
  end
end
```

---

## Phase 5: Integrate Controller with Services ✅

### 5.1 Complete Controller Implementation ✅

**Completed:**
- [x] Integrated MealService into controller
- [x] Integrated LLMService for automatic estimation on create
- [x] Implemented proper error handling with changeset formatting
- [x] Added routes: `GET /meals/:id`, `POST /meals/:id/confirm`
- [x] Added JSON serialization with proper date/decimal formatting

**Complete controller:**
```elixir
defmodule JournalWeb.MealController do
  use JournalWeb, :controller

  alias Journal.Services.MealService
  alias Journal.Services.LLMService

  # POC: Using constant patient_id. In production, extract from Bearer token.
  @poc_patient_id 1

  def create(conn, params) do
    patient_id = get_patient_id(conn)

    with {:ok, meal} <- MealService.create_meal(patient_id, params),
         {:ok, estimation} <- LLMService.estimate_meal(nil, meal.original_description),
         {:ok, updated_meal} <- MealService.update_with_estimation(meal, estimation) do
      conn
      |> put_status(:created)
      |> json(%{
        data: %{
          id: updated_meal.id,
          date: updated_meal.date,
          meal_type: updated_meal.meal_type,
          original_description: updated_meal.original_description,
          protein_g: updated_meal.protein_g,
          carbs_g: updated_meal.carbs_g,
          fat_g: updated_meal.fat_g,
          calories_kcal: updated_meal.calories_kcal,
          weight_g: updated_meal.weight_g,
          ai_comment: updated_meal.ai_comment,
          status: updated_meal.status
        }
      })
    else
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  # POC: Returns constant patient_id. Replace with Bearer token extraction.
  defp get_patient_id(_conn), do: @poc_patient_id

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
```

---

## Phase 6: Testing

### 6.1 Unit Tests

**Tasks:**
- [ ] Create test helpers and fixtures
- [ ] Test `MealEntry` changeset validations
- [ ] Test `MealService.create_meal/2`
- [ ] Test `LLMService.estimate_meal/2` (mock)

**Test example:**
```elixir
# test/journal/services/meal_service_test.exs
defmodule Journal.Services.MealServiceTest do
  use Journal.DataCase

  alias Journal.Services.MealService
  alias Journal.Meals.MealEntry

  # POC: Using constant patient_id
  @test_patient_id 1

  describe "create_meal/2" do
    test "creates a meal entry with pending status" do
      attrs = %{
        "meal_type" => "breakfast",
        "original_description" => "2 eggs and toast"
      }

      assert {:ok, %MealEntry{} = meal} = MealService.create_meal(@test_patient_id, attrs)
      assert meal.status == :pending
      assert meal.meal_type == :breakfast
      assert meal.patient_id == @test_patient_id
    end

    test "returns error for invalid meal_type" do
      attrs = %{
        "meal_type" => "invalid",
        "original_description" => "test"
      }

      assert {:error, changeset} = MealService.create_meal(@test_patient_id, attrs)
      assert "is invalid" in errors_on(changeset).meal_type
    end
  end
end
```

---

### 6.2 Integration Tests

**Tasks:**
- [ ] Test full request/response cycle
- [ ] Test error handling
- [ ] Test database persistence

**Test example:**
```elixir
# test/journal_web/controllers/meal_controller_test.exs
defmodule JournalWeb.MealControllerTest do
  use JournalWeb.ConnCase

  describe "POST /meals" do
    test "creates meal and returns 201", %{conn: conn} do
      conn = post(conn, ~p"/meals", %{
        meal_type: "breakfast",
        original_description: "2 eggs and toast"
      })

      assert %{
        "data" => %{
          "id" => _,
          "status" => "pending",
          "meal_type" => "breakfast"
        }
      } = json_response(conn, 201)
    end

    test "returns 422 for invalid data", %{conn: conn} do
      conn = post(conn, ~p"/meals", %{})

      assert json_response(conn, 422)["errors"]
    end
  end
end
```

---

## Phase 7: AWS Lambda Deployment ✅

### 7.1 Lambda Configuration ✅

Phoenix can run on AWS Lambda using the **Lambda Web Adapter**. This approach:
- Requires minimal code changes
- Uses the same Phoenix app
- Handles HTTP events natively

**Completed:**
- [x] Created `serverless.yml` configuration
- [x] Configured Lambda Web Adapter layer (ARM64)
- [x] Setup environment variables (DATABASE_URL, SECRET_KEY_BASE, etc.)
- [x] Configured SSL for RDS connection (`ssl: true, ssl_opts: [verify: :verify_none]`)
- [x] Configured VPC for Lambda to access RDS
- [x] Added dual routes (`/health` and `/journal/*`) for Lambda readiness check and API Gateway

**serverless.yml:**
```yaml
service: balansi-journal

frameworkVersion: '4'

provider:
  name: aws
  runtime: provided.al2023
  region: us-east-2
  architecture: arm64
  memorySize: 512
  timeout: 30
  stage: ${opt:stage, 'dev'}
  environment:
    STAGE: ${self:provider.stage}
    DATABASE_URL: ${env:DATABASE_URL}
    OPENAI_API_KEY: ${env:OPENAI_API_KEY}
    PHX_HOST: ${env:PHX_HOST, 'localhost'}
    SECRET_KEY_BASE: ${env:SECRET_KEY_BASE}
    AWS_LWA_INVOKE_MODE: response_stream

functions:
  api:
    handler: bootstrap
    layers:
      - arn:aws:lambda:us-east-2:753240598075:layer:LambdaAdapterLayerArm64:22
    events:
      - httpApi:
          path: /journal/{proxy+}
          method: any
      - httpApi:
          path: /journal
          method: any

package:
  patterns:
    - '!**'
    - '_build/prod/rel/journal/**'
    - 'bootstrap'
```

---

### 7.2 Create Bootstrap Script ✅

**Completed:**
- [x] Created `bootstrap` script for Lambda
- [x] Configured proper startup

**bootstrap script:**
```bash
#!/bin/sh
set -e

cd /var/task/_build/prod/rel/journal
exec bin/journal start
```

---

### 7.3 Build & Deploy ✅

**Completed:**
- [x] Created release configuration in `mix.exs`
- [x] Configured Docker build for Linux ARM64 (Debian Bookworm)
- [x] Built release using Docker for Lambda compatibility
- [x] Deployed to AWS Lambda successfully

**Build commands (Makefile):**
```bash
# Build release for Lambda (uses Docker)
make build

# Deploy
SERVERLESS_STAGE=dev make deploy

# Deploy function only (faster)
SERVERLESS_STAGE=dev make deploy-function
```

**Deployment challenges resolved:**
- OpenSSL compatibility: Used Debian Bookworm image with compatible OpenSSL version
- glibc compatibility: Used `provided.al2023` runtime with matching glibc
- Database SSL: Added `ssl: true, ssl_opts: [verify: :verify_none]` to Repo config
- VPC networking: Configured Lambda to access RDS in same VPC

---

## Phase 8: Verification & Documentation

### 8.1 End-to-End Verification ✅

**Completed:**
- [x] Test deployed endpoint with curl
- [x] Verify health check endpoint works
- [x] Check CloudWatch logs
- [ ] Verify database records are created (requires VPC config)
- [ ] Verify response format matches API spec

**Deployed endpoints:**
```
https://kt8oj1bwyh.execute-api.us-east-2.amazonaws.com/journal/health
https://kt8oj1bwyh.execute-api.us-east-2.amazonaws.com/journal/meals
```

**Test commands:**
```bash
# Health check
curl https://kt8oj1bwyh.execute-api.us-east-2.amazonaws.com/journal/health
# → {"status":"ok","service":"journal","timestamp":"..."}

# Create meal
curl -X POST https://kt8oj1bwyh.execute-api.us-east-2.amazonaws.com/journal/meals \
  -H "Content-Type: application/json" \
  -d '{
    "date": "2025-12-05",
    "meal_type": "breakfast",
    "original_description": "2 eggs and toast with avocado"
  }'
```

---

### 8.2 Documentation

**Tasks:**
- [ ] Update README with setup instructions
- [ ] Create OpenAPI specification (`openapi.yaml`)
- [ ] Add deployment notes

### 8.3 OpenAPI Specification

**Create `openapi.yaml` with:**

```yaml
openapi: 3.0.3
info:
  title: Balansi Journal API
  version: 1.0.0
  description: API for meal logging and nutritional tracking

paths:
  /health:
    get:
      summary: Health check
      responses:
        '200':
          description: Service is healthy

  /meals:
    get:
      summary: List meals
      parameters:
        - name: date
          in: query
          schema:
            type: string
            format: date
        - name: status
          in: query
          schema:
            type: string
            enum: [pending, processing, in_review, confirmed]
      responses:
        '200':
          description: List of meals

    post:
      summary: Create meal
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateMealRequest'
      responses:
        '201':
          description: Meal created and processed
        '422':
          description: Validation error

  /meals/{id}:
    get:
      summary: Get meal by ID
      responses:
        '200':
          description: Meal details
        '404':
          description: Not found

  /meals/{id}/confirm:
    post:
      summary: Confirm meal after review
      responses:
        '200':
          description: Meal confirmed
        '422':
          description: Invalid status transition

components:
  schemas:
    CreateMealRequest:
      type: object
      required:
        - date
        - meal_type
        - original_description
      properties:
        date:
          type: string
          format: date
        meal_type:
          type: string
          enum: [breakfast, lunch, snack, dinner]
        original_description:
          type: string

    MealEntry:
      type: object
      properties:
        id:
          type: integer
        patient_id:
          type: integer
        date:
          type: string
          format: date
        meal_type:
          type: string
        original_description:
          type: string
        protein_g:
          type: number
        carbs_g:
          type: number
        fat_g:
          type: number
        calories_kcal:
          type: integer
        weight_g:
          type: integer
        ai_comment:
          type: string
        status:
          type: string
          enum: [pending, processing, in_review, confirmed]
        has_manual_override:
          type: boolean
```

---

## File Structure

```
services/journal/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── prod.exs
│   ├── runtime.exs
│   └── test.exs
├── lib/
│   ├── journal/
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   ├── meals/
│   │   │   └── meal_entry.ex
│   │   └── services/
│   │       ├── llm_service.ex
│   │       └── meal_service.ex
│   └── journal_web/
│       ├── controllers/
│       │   ├── health_controller.ex
│       │   └── meal_controller.ex
│       ├── router.ex
│       └── endpoint.ex
├── priv/
│   └── repo/
│       └── migrations/
│           └── YYYYMMDDHHMMSS_create_meal_entries.exs
├── test/
│   ├── journal/
│   │   └── services/
│   │       └── meal_service_test.exs
│   ├── journal_web/
│   │   └── controllers/
│   │       └── meal_controller_test.exs
│   ├── support/
│   │   ├── data_case.ex
│   │   ├── conn_case.ex
│   │   └── factory.ex
│   └── test_helper.exs
├── .env.example
├── .formatter.exs
├── .gitignore
├── bootstrap
├── Makefile
├── mix.exs
├── mix.lock
├── openapi.yaml
├── README.md
└── serverless.yml
```

---

## Estimated Timeline

| Phase | Description | Estimate |
|-------|-------------|----------|
| 1 | Project Setup & Configuration | 2-3 hours |
| 2 | Basic Endpoint (200 OK) | 1-2 hours |
| 3 | Database & Migrations | 2-3 hours |
| 4 | Service Layer | 2-3 hours |
| 5 | Controller Integration | 1-2 hours |
| 6 | Testing | 3-4 hours |
| 7 | AWS Lambda Deployment | 3-4 hours |
| 8 | Verification & Docs | 1-2 hours |
| **Total** | | **15-23 hours** |

---

## Prerequisites

Before starting, ensure you have:

1. **Elixir installed** (v1.15+)
   ```bash
   brew install elixir
   ```

2. **PostgreSQL running locally**
   ```bash
   brew services start postgresql
   ```

3. **Access to AWS account** with appropriate permissions

4. **Serverless Framework** installed
   ```bash
   npm install -g serverless
   ```

5. **Environment variables** configured:
   - `DATABASE_URL`
   - `SECRET_KEY_BASE`
   - `OPENAI_API_KEY` (for later phases)

---

## Notes & Considerations

### Lambda Deployment Options

**Option A: Lambda Web Adapter (Recommended for POC)**
- Uses standard Phoenix server
- Minimal code changes
- Good for prototyping
- May have slower cold starts

**Option B: Custom Lambda Handler**
- More complex setup
- Better cold start performance
- Requires custom handler code

For this POC, we'll use **Option A** to get up and running quickly.

### Database Considerations

- For POC, the journal service uses its own database (`journal_dev`)
- No user table is created; `user_id` is stored as a simple integer
- In production, will share the same PostgreSQL database as the auth service
- Migrations should be coordinated to avoid conflicts

### Future Phases (Out of Scope for POC)

- OpenAI integration for real LLM calls
- Authentication/Authorization middleware
- Rate limiting
- Caching layer
- Monitoring and alerting
