# Keycloak Configuration

Keycloak deployment with realm configuration management and Docker Secrets.

## Prerequisites

- Docker (with Compose V2)
- [Task](https://taskfile.dev/) - Task runner
- yq v4+ - YAML processor
- jq - JSON processor

```bash
task check  # Verify dependencies
```

## Quick Start (Local Development)

```bash
# 1. Setup secrets (one-time, initializes Docker Swarm for secrets)
task secrets:setup

# 2. Create .env from template
cp .env.example .env
# Edit .env with your hostname/ports

# 3. Build realm config
task config:build:smartfactory:dev

# 4. Start Keycloak
task dev:up

# 5. Import config (after Keycloak is healthy)
task config:import

# Access: https://localhost:7444
```

## Tasks Overview

### Config Build
```bash
task config:build:smartfactory:dev           # Base smartfactory config
task config:build:smartfactory:umsicht:dev   # With umsicht customer overlay
task config:build:smartfactory:umsicht:prod  # Production (no placeholders)
task config:build:iot-gateway:dev            # IoT Gateway config
```

### Development
```bash
task dev:up      # Start Postgres + Keycloak
task dev:down    # Stop stack
task dev:logs    # Follow Keycloak logs
task dev:clean   # Remove everything including data
```

### Config Import
```bash
task config:import   # Import merged config into running Keycloak
```

### Secrets
```bash
task secrets:setup   # Interactive setup (creates Docker Secrets)
task secrets:list    # List existing secrets
task secrets:remove  # Remove all secrets
```

### Docker Image
```bash
task docker:build -- 26.1.0    # Build image with tag
task docker:push -- 26.1.0     # Push to registry
```

### Production Deployment
```bash
task deploy   # Full deployment (requires secrets + merged config)
```

### Release Package
```bash
task release:smartfactory:umsicht:prod   # Create deployment tarball
```

## Project Structure

```
keycloak/
├── compose.yaml          # Docker Compose with secrets
├── Dockerfile            # Keycloak image
├── Taskfile.yaml         # All tasks
├── .env.example          # Environment template
├── config/
│   ├── smartfactory/     # Base configs
│   │   ├── realm.yaml
│   │   ├── clients.yaml
│   │   ├── roles.yaml
│   │   ├── groups.yaml
│   │   └── users.yaml
│   ├── iot-gateway/
│   └── merged/           # Generated (gitignored)
├── scripts/
│   ├── build-realm.sh
│   ├── setup-secrets.sh
│   ├── deploy.sh
│   └── ...
└── certs/                # TLS certificates
```

## Secrets Management

This setup uses **Docker Secrets** for secure credential management.

### Initial Setup (once per server)
```bash
task secrets:setup
```

This will:
1. Initialize Docker Swarm (local mode, no cluster)
2. Prompt for each secret value
3. Store secrets encrypted in Docker

### Secrets Used
| Secret | Used By |
|--------|---------|
| `admin_password` | Keycloak admin login |
| `db_password` | PostgreSQL + Keycloak DB connection |
| `keystore_password` | TLS keystore |
| `gateway_secret` | Gateway client secret |
| `user_secret` | User client secret |
| `node_red_secret` | Node-RED client secret |

### Why Docker Secrets?
- Secrets are encrypted at rest
- Never written to disk as plaintext
- Containers access via `/run/secrets/`
- Survives container restarts

## Customer-Specific Configs

For customer deployments, configs are merged from:
1. Base product config (`config/<product>/`)
2. Customer overlay (from separate repo)

Set in `.env`:
```
CUSTOMER_CONFIG_REPO_URL=https://git.example.com/customer-configs.git
```

Expected structure in customer repo:
```
<customer>/<product>/keycloak/
├── clients.yaml
├── users.yaml
└── ...
```

## Production Deployment

1. Build release package:
   ```bash
   task release:smartfactory:umsicht:prod
   ```

2. Transfer `dist/keycloak-*.tar.gz` to server

3. On server:
   ```bash
   tar -xzf keycloak-*.tar.gz
   cd keycloak
   
   # Setup secrets (interactive, one-time)
   ./scripts/setup-secrets.sh
   
   # Create .env
   cp .env.example .env
   # Edit .env
   
   # Deploy
   ./scripts/deploy.sh
   ```
