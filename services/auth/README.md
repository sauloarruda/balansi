# Balansi Auth Service

Balansi authentication service in Go, deployed on AWS Lambda.

## Quick Start

### Prerequisites

- Go 1.21+
- Node.js and npm (for cognito-local)
- PostgreSQL database running locally

### Setup (First Time Only)

1. **Install dependencies:**

```bash
make deps
make migrate-install
```

2. **Create `.env` file:**

```bash
cp .env.example .env
```

3. **Edit `.env` with your database credentials:**

```bash
DATABASE_URL=postgresql://user:password@localhost:5432/balansi_development?sslmode=disable
ENCRYPTION_SECRET=your-secret-key-here
```

4. **Generate encryption secret (optional):**

```bash
make generate-secret
# Copy the generated secret to your .env file
```

5. **Start cognito-local and setup:**

```bash
make cognito-local-up
make cognito-local-setup
```

6. **Copy the Cognito IDs from the output to your `.env` file:**
   The `cognito-local-setup` command will display:

```
COGNITO_USER_POOL_ID=local_xxxxx
COGNITO_CLIENT_ID=xxxxx
COGNITO_ENDPOINT=http://localhost:9229
```

7. **Run database migrations:**

```bash
make migrate-up
```

### Running the Service

```bash
make dev
```

The server will start on `http://localhost:3000`

### Testing

```bash
curl -X POST http://localhost:3000/auth/sign-up \
  -H "Content-Type: application/json" \
  -d '{"name": "John Doe", "email": "john@example.com"}'
```

## Environment Variables

Create a `.env` file in the `services/auth/` directory with the following variables:

```bash
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/balansi_development?sslmode=disable

# Encryption (generate with: make generate-secret)
ENCRYPTION_SECRET=your-32-character-secret-here

# Cognito (get these from: make cognito-local-setup)
COGNITO_USER_POOL_ID=local_xxxxx
COGNITO_CLIENT_ID=xxxxx
COGNITO_ENDPOINT=http://localhost:9229
```

**Note:** For local development, always use `COGNITO_ENDPOINT=http://localhost:9229` to connect to cognito-local.

## Project Structure

```
services/auth/
  cmd/
    api/
      main.go          # Application entry point
  internal/
    handlers/          # HTTP handlers
      signup.go
    services/          # Business logic
      signup_service.go
    repositories/      # Database access
      user_repository.go
    cognito/           # Cognito client
      client.go
    config/            # Configuration
      config.go
    models/            # Data models
      user.go
  migrations/          # Database migrations
    000001_create_users_table.up.sql
    000001_create_users_table.down.sql
  scripts/             # Utility scripts
    setup-cognito.sh
  go.mod
  serverless.yml       # Serverless Framework configuration
  Makefile             # Useful commands
```

## Available Commands

### Development

- `make deps` - Install Go dependencies
- `make dev` - Start local development server
- `make build-local` - Build for local testing

### Cognito Local

- `make cognito-local-up` - Start cognito-local emulator
- `make cognito-local-setup` - Create User Pool and Client
- `make cognito-local-down` - Stop cognito-local

### Database

- `make migrate-up` - Run database migrations
- `make migrate-down` - Rollback last migration
- `make migrate-install` - Install migrate CLI tool

### Utilities

- `make generate-secret` - Generate encryption secret

### Deployment

- `make build` - Build for Lambda (Linux ARM64)
- `make deploy` - Deploy to AWS Lambda
- `make deploy-function` - Deploy function only

## Deployment

### Build for Lambda

```bash
make build
```

Creates the `bootstrap` binary compiled for Linux ARM64 (required for AWS Lambda).

### Deploy to AWS

1. Create environment-specific `.env` file:

```bash
cp .env.example .env.dev
```

2. Edit `.env.dev` with production values:

   - Use production database URL
   - Use real AWS Cognito User Pool ID and Client ID
   - Leave `COGNITO_ENDPOINT` empty for production

3. Deploy:

```bash
make deploy                    # Deploy to 'dev' stage
SERVERLESS_STAGE=prod make deploy  # Deploy to 'prod' stage
```

**Note:** All `.env.*` files are gitignored and won't be committed.

## API Endpoints

### POST /auth/sign-up

Creates a new user account.

**Request:**

```json
{
  "name": "John Doe",
  "email": "john@example.com"
}
```

**Success Response (201):**

```json
{
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com"
}
```

**Error Responses:**

- `400` - Invalid request body or missing required fields
- `409` - User with this email already exists
- `500` - Internal server error

## Next Steps

- [x] Implement real sign-up logic
- [x] PostgreSQL integration
- [x] AWS Cognito integration
- [ ] Input validation
- [ ] Complete error handling
- [ ] Unit and integration tests
