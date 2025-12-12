# Keycloak with Config CLI

Keycloak deployment with realm configuration management using [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli).

## Overview

This repository provides:
- Custom Keycloak Docker image with health checks
- Realm configuration as code (YAML)
- Config merging for product/customer-specific deployments
- Azure DevOps pipeline for CI/CD

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | with Compose V2 | Container runtime |
| [Task](https://taskfile.dev/) | 3.x | Task runner |
| yq | 4.x | YAML processing |
| jq | 1.6+ | JSON processing |

```bash
task check  # Verify all dependencies
```

## Quick Start

```bash
# 1. Create environment file
cp .env.example .env
# Edit .env with your values

# 2. Build realm configuration
task config:build:smartfactory

# 3. Start Keycloak + PostgreSQL
docker compose up -d

# 4. Wait for healthy state
docker compose logs -f keycloak
# Look for: "Keycloak started successful!"

# 5. Import realm configuration
task config:import
```

Access Keycloak at `https://localhost:7444` (or your configured port).

Default credentials: `admin` / `admin`

## Project Structure

```
keycloak/
├── compose.yaml              # Keycloak + PostgreSQL
├── compose.keycloak-cli.yaml # Config CLI (import)
├── Dockerfile                # Custom Keycloak image
├── Taskfile.yaml             # Task definitions
├── .env.example              # Environment template
│
├── config/
│   ├── smartfactory/         # Product base configuration
│   │   ├── realm.yaml        # Realm settings
│   │   ├── clients.yaml      # OAuth clients
│   │   ├── roles.yaml        # Realm roles
│   │   ├── groups.yaml       # User groups
│   │   ├── users.yaml        # Users
│   │   └── client-scopes.yaml
│   │
│   ├── iot-gateway/          # Another product config
│   └── merged/               # Generated output (gitignored)
│
├── scripts/
│   ├── build-config.sh       # Merge configurations
│   ├── add-userprofile.sh    # User profile API workaround
│   ├── kc-start.sh           # Keycloak entrypoint
│   └── check-dependencies.sh
│
├── certs/
│   └── name.p12              # TLS keystore
│
└── .azuredevops/
    └── pipelines/
        └── azure-build-pipeline.yaml
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DHOSTNAME` | localhost | Keycloak hostname |
| `PORT_KEYCLOAK` | 7444 | HTTPS port |
| `PORT_GATEWAY` | 443 | Gateway port (for redirects) |
| `TAG_KEYCLOAK` | 26.1.0 | Keycloak version |
| `TAG_POSTGRES` | 15 | PostgreSQL version |
| `REGISTRY` | atrdocker01.atr.local:7444 | Docker registry |
| `KC_ADMIN_PASSWORD` | admin | Keycloak admin password |
| `DB_PASSWORD` | admin | PostgreSQL password |
| `KEYSTORE_PASSWORD` | changeit | TLS keystore password |
| `GATEWAY_SECRET` | - | Gateway client secret |
| `USER_SECRET` | - | User client secret |
| `NODE_RED_SECRET` | - | Node-RED client secret |

### Variable Substitution

The config CLI supports variable substitution in YAML files. Use `$(VARIABLE)` syntax:

```yaml
# config/smartfactory/clients.yaml
clients:
  - clientId: gateway-client
    secret: $(GATEWAY_SECRET)
    redirectUris:
      - https://$(DHOSTNAME):$(PORT_GATEWAY)/*
```

Variables are resolved from environment at import time.

## Tasks

### Configuration

```bash
# Build base smartfactory config
task config:build:smartfactory

# Build with customer overlay
task config:build:smartfactory:umsicht

# Import into running Keycloak
task config:import
```

### Docker Images

```bash
# Build Keycloak image
task docker:build:keycloak

# Push to registry
task docker:push:keycloak

# Mirror config-cli from Docker Hub to registry
task docker:push:keycloak-cli

# Push both images to AWS
task aws:push
```

### Utilities

```bash
# Check dependencies
task check
```

## Customer-Specific Configurations

For customer deployments, configurations are merged in layers:

1. **Base** – Product config from `config/<product>/`
2. **Customer** – Overlay from external repository

### Setup

Set the customer config repository in `.env`:

```bash
CUSTOMER_CONFIG_REPO_URL=https://git.example.com/customer-configs.git
```

Expected structure in customer repo:

```
<customer>/<product>/keycloak/
├── clients.yaml      # Overrides/additions
├── users.yaml
├── roles.yaml
├── groups.yaml
├── client-scopes.yaml
└── ldap.yaml         # LDAP configuration
```

### Merge Behavior

- Arrays are merged by ID field (e.g., `clientId`, `username`)
- Customer entries override base entries with same ID
- New entries are added

## Docker Compose

### Start Stack

```bash
# Start Keycloak + PostgreSQL
docker compose up -d

# View logs
docker compose logs -f keycloak

# Stop
docker compose down

# Stop and remove data
docker compose down -v
```

### Import Configuration

```bash
# Uses separate compose file
task config:import

# Or manually:
./scripts/add-userprofile.sh smartfactory
docker compose -f compose.keycloak-cli.yaml up
```

## Azure DevOps Pipeline

The pipeline supports:

### Parameters

| Parameter | Options | Description |
|-----------|---------|-------------|
| `build_images` | true/false | Build and push Docker images |
| `aws` | true/false | Push to AWS ECR |
| `product` | smartfactory, iot-gateway | Product to build |
| `customer` | atr, umsicht | Customer overlay |

### Stages

1. **BuildImages** (optional)
   - Builds Keycloak image
   - Mirrors config-cli
   - Pushes to registry (and optionally AWS)

2. **BuildConfig**
   - Builds merged realm configuration
   - Publishes artifact with config files

### Required Variable Groups

- `AWS Upload` – AWS credentials and prefix
- `Keycloak Customer Config` – Customer repo URL

## TLS Certificate

Place your PKCS12 keystore at `certs/name.p12`.

Generate a self-signed certificate for development:

```bash
keytool -genkeypair \
  -alias server \
  -keyalg RSA \
  -keysize 2048 \
  -validity 365 \
  -keystore certs/name.p12 \
  -storetype PKCS12 \
  -storepass changeit \
  -dname "CN=localhost"
```

## Troubleshooting

### Keycloak won't start

Check logs:
```bash
docker compose logs keycloak
```

Common issues:
- PostgreSQL not ready – wait for health check
- Certificate not found – verify `certs/name.p12` exists
- Port already in use – change `PORT_KEYCLOAK` in `.env`

### Config import fails

1. Ensure Keycloak is healthy:
   ```bash
   curl -k https://localhost:7444/health/ready
   ```

2. Check config CLI logs:
   ```bash
   docker compose -f compose.keycloak-cli.yaml logs
   ```

3. Validate merged config:
   ```bash
   yq eval '.' config/merged/smartfactory-realm.yaml
   ```

### Network errors

If you see "network not found":
```bash
docker compose down
docker network prune -f
docker compose up -d
```

## Development

### Adding a New Client

1. Edit `config/<product>/clients.yaml`
2. Rebuild: `task config:build:<product>`
3. Re-import: `task config:import`

### Adding a New Product

1. Create directory: `config/<product>/`
2. Add configuration files (at minimum `realm.yaml`)
3. Add task to `Taskfile.yaml`
4. Update pipeline if needed

### Testing Configuration Changes

```bash
# Rebuild and reimport
task config:build:smartfactory
task config:import

# Or start fresh
docker compose down -v
docker compose up -d
# Wait for healthy...
task config:import
```