# Journal Service

The **Journal** microservice is the core daily tracking experience of Balansi. It handles meal logging, exercise tracking, and AI-assisted nutritional feedback.

## Tech Stack

- **Language:** Elixir 1.15+
- **Framework:** Phoenix 1.8 (API mode)
- **Database:** PostgreSQL
- **Deployment:** AWS Lambda (via Lambda Web Adapter)

## Prerequisites

- Elixir 1.15+ (`brew install elixir`)
- PostgreSQL running locally
- Node.js (for Serverless Framework)

## Getting Started

### 1. Install Dependencies

```bash
make deps
```

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with your configuration
```

Generate a secret key:

```bash
make generate-secret
# Add the output to SECRET_KEY_BASE in .env
```

### 3. Setup Database

```bash
make setup
```

### 4. Run Locally

```bash
make dev
```

The API will be available at `http://localhost:4000`

## Available Commands

Run `make help` to see all available commands:

```
Development:
  make setup            - Install dependencies and setup database
  make deps             - Install/update dependencies
  make dev              - Run API locally (development mode)

Build & Deploy:
  make build            - Build release for Lambda
  make deploy           - Deploy to AWS Lambda
  make clean            - Remove generated files

Database:
  make migrate-up       - Run database migrations
  make migrate-down     - Rollback last migration
  make migrate-reset    - Reset database

Testing:
  make test             - Run all tests
  make test-coverage    - Run tests with coverage

Code Quality:
  make lint             - Run credo linter
  make format           - Format code
  make precommit        - Run all checks before commit
```

## API Endpoints

### Health Check

```
GET /health
```

### Meals

```
POST /meals
GET  /meals?date=YYYY-MM-DD
```

> **Note:** For the POC, `user_id` is obtained from a constant. In production, it will be extracted from the Bearer token.

## Project Structure

```
lib/
├── journal/
│   ├── application.ex       # Application startup
│   ├── repo.ex             # Database repository
│   ├── accounts/           # User-related schemas
│   ├── journal/            # Journal domain (meals, exercises)
│   └── services/           # Business logic
└── journal_web/
    ├── controllers/        # HTTP controllers
    ├── router.ex           # Route definitions
    └── endpoint.ex         # Phoenix endpoint
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `DATABASE_URL` | PostgreSQL connection string | Yes |
| `SECRET_KEY_BASE` | Phoenix secret key | Yes (prod) |
| `OPENAI_API_KEY` | OpenAI API key | For AI features |
| `FRONTEND_DOMAIN` | Allowed CORS origins | Prod |
| `PHX_HOST` | Host for URL generation | Prod |
| `PORT` | Server port | No (default: 4000) |
| `COGNITO_DOMAIN` | Cognito Hosted UI domain (e.g., `https://your-domain.auth.us-east-2.amazoncognito.com`) | Yes |
| `COGNITO_CLIENT_ID` | Cognito App Client ID | Yes |
| `COGNITO_REDIRECT_URI` | Redirect URI after Cognito callback (must match Cognito config) | Yes |

## Testing

```bash
# Run all tests
make test

# Run with coverage
make test-coverage

# Run specific test file
mix test test/journal/services/meal_service_test.exs
```

## Deployment

### AWS Lambda

1. Configure environment:
   ```bash
   cp .env.example .env.dev
   # Edit with production values
   ```

2. Deploy:
   ```bash
   SERVERLESS_STAGE=dev make deploy
   ```

## License

This project is licensed under the [Creative Commons Attribution-NonCommercial 4.0 International Public License](https://creativecommons.org/licenses/by-nc/4.0/legalcode).

You are free to:
- **Share** — copy and redistribute the material in any medium or format
- **Adapt** — remix, transform, and build upon the material

Under the following terms:
- **Attribution** — You must give appropriate credit, provide a link to the license, and indicate if changes were made
- **NonCommercial** — You may not use the material for commercial purposes
- **No additional restrictions** — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits
