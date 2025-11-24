# Balansi

Balansi is a fast, minimalist nutrition and training journal designed to give users clear daily feedback with almost no friction.

Instead of complex screens and heavy data entry, the user logs meals and workouts in free text and automatically receives macro calculations, calorie estimates, total protein, daily balance, and a score based on objective criteria.

The goal is to turn daily tracking into something that takes seconds but still delivers meaningful clarity about the quality of the day.


## What Balansi Does

The v1 is intentionally minimal: no charts, no weekly dashboards, no external integrations, and no full conversational AI.

Just the core loop of logging, calculating, and evaluating. With a clean interface and an internal engine powered by LLMs to interpret free-text input, Balansi provides a reliable daily summary, practical guidance, and a streamlined experience that encourages consistency without hassle.

## Documentation

- [Project Pitch](doc/PITCH-v1.md) - Vision, scope, and goals for Balansi v1

## Project Structure

This repository is organized as a monorepo with the following services:

```
balansi/
├── services/
│   ├── auth/          # Go backend service (AWS Lambda)
│   └── web/           # SvelteKit frontend application
├── .cursor/           # Cursor AI rules for each service
├── .vscode/           # VSCode/Cursor workspace settings
└── Makefile           # Monorepo commands
```

### Services

- **`services/auth`** - Go backend service for authentication and user management, deployed on AWS Lambda. See [Auth Service README](services/auth/README.md) for details.

- **`services/web`** - SvelteKit frontend application with TypeScript, TailwindCSS, and Preline UI components. See [Web Service README](services/web/README.md) for details.

## Quick Start

### Prerequisites

- **Go** 1.21+ (for auth service)
- **Node.js** 20+ and npm (for web service)
- **PostgreSQL** (for local development)
- **Docker** (for running tests with testcontainers)

### Installation

1. **Clone the repository:**

```bash
git clone <repository-url>
cd balansi
```

2. **Install dependencies:**

```bash
make install-deps
```

This will install dependencies for both services.

3. **Set up environment variables:**

- Auth service: Copy `services/auth/.env.example` to `services/auth/.env` and configure
- Web service: No environment variables needed for local development

4. **Start development servers:**

```bash
make dev
```

This starts both services:
- Auth API: `http://localhost:3000`
- Web app: `http://localhost:8080`

## Available Commands

To see all available commands, run:

```bash
make help
```

Each service also has its own `Makefile` with additional commands. Navigate to the service directory to see service-specific commands:

```bash
cd services/auth && make help
cd services/web && make help
```

## Development Workflow

1. **Start both services:**
   ```bash
   make dev
   ```

2. **Run tests:**
   ```bash
   make test
   ```

3. **Run linters:**
   ```bash
   make lint
   ```

4. **Format code:**
   ```bash
   make format-web  # For web service
   cd services/auth && make lint-fix  # For auth service
   ```

## Project Documentation

- [Auth Service Documentation](services/auth/README.md) - Go backend service details
- [Web Service Documentation](services/web/README.md) - SvelteKit frontend details

## Technology Stack

### Auth Service
- **Language:** Go 1.21+
- **Framework:** AWS Lambda
- **Database:** PostgreSQL
- **Authentication:** AWS Cognito
- **Testing:** testify, testcontainers-go
- **Linting:** golangci-lint

### Web Service
- **Framework:** SvelteKit 2.0
- **Language:** TypeScript
- **Styling:** TailwindCSS + Preline UI
- **Testing:** Playwright
- **Linting:** ESLint + Prettier
- **API Client:** Generated from OpenAPI spec

## Contributing

1. Create a branch from `main`
2. Make your changes
3. Run tests and linters: `make test && make lint`
4. Commit using conventional commits (e.g., `feat: add new feature`)
5. Push and create a pull request

## License

This project is licensed under the [Creative Commons Attribution-NonCommercial 4.0 International Public License](https://creativecommons.org/licenses/by-nc/4.0/legalcode).

You are free to:
- **Share** — copy and redistribute the material in any medium or format
- **Adapt** — remix, transform, and build upon the material

Under the following terms:
- **Attribution** — You must give appropriate credit, provide a link to the license, and indicate if changes were made
- **NonCommercial** — You may not use the material for commercial purposes
- **No additional restrictions** — You may not apply legal terms or technological measures that legally restrict others from doing anything the license permits
