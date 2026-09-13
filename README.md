# HouseForce Infrastructure

This repository contains the deployment orchestration for the HouseForce platform, providing ingress routing, TLS certificates, automated continuous deployment, and environment separation between Test and Production.

---

## Architecture

- **Traefik (v2.11)**: Edge reverse proxy and ingress controller handling automated Let's Encrypt SSL/TLS certificates and routing:
  - `${DOMAIN}` & `www.${DOMAIN}` -> Next.js Marketing Frontend (`houseforce-frontend`)
  - `portal.${DOMAIN}` -> Next.js Customer Portal (`houseforce-portal`)
  - `api.${DOMAIN}` -> Strapi Headless CMS (`houseforce-backend`)
  - `deploy.${DOMAIN}` -> Watchtower HTTP webhook receiver (`watchtower`)
  - `traefik.${DOMAIN}` / `dns.${DOMAIN}` -> Traefik dashboard (protected by HTTP Basic Auth)
- **Watchtower**: Automatically triggers rolling container updates from GitHub Container Registry (GHCR) when triggered via authorized webhooks or API calls.
- **Environments**:
  - **Test**: Self-contained Droplet deployment running local PostgreSQL and MinIO S3 containers via `docker-compose.test.yml`.
  - **Production**: High-availability Droplet deployment utilizing DigitalOcean Managed PostgreSQL and DigitalOcean Spaces (S3).

---

## Getting Started & Bootstrap

### 1. Droplet Provisioning
Run the appropriate bootstrap script once on a fresh Ubuntu droplet as `root`:

- **Production Droplet**:
  ```bash
  curl -sSL https://raw.githubusercontent.com/Serathian/houseforce-infra/main/startup.sh | bash
  # Or run locally from cloned repo:
  ./startup.sh
  ```
- **Test Droplet**:
  ```bash
  curl -sSL https://raw.githubusercontent.com/Serathian/houseforce-infra/main/startup-test.sh | bash
  # Or run locally from cloned repo:
  ./startup-test.sh
  ```

The script will automatically configure 2GB swap, install Docker and Compose v2, set up a dedicated `deploy` user, prompt for environment configuration, and create the `.env` file.

### 2. Manual Environment Setup
If setting up without the startup scripts:
```bash
cp .env.example .env
# Edit .env with your domain, credentials, and secrets
chmod 600 .env
```

---

## Running the Services

### Test Environment
```bash
# Validate configuration
docker compose -f docker-compose.yml -f docker-compose.test.yml config

# Start test stack
docker compose -f docker-compose.yml -f docker-compose.test.yml up -d

# Stop test stack
docker compose -f docker-compose.yml -f docker-compose.test.yml down
```

### Production Environment
```bash
# Validate configuration
docker compose config

# Pull latest images from GHCR
docker compose pull

# Start production stack
docker compose up -d

# Stop production stack
docker compose down
```

---

## Continuous Deployment via Watchtower

When images are built and pushed to GHCR (e.g. via GitHub Actions in the `houseforce` repository), deployments can be triggered instantly:

```bash
curl -H "Authorization: Bearer <WATCHTOWER_TOKEN>" \
     -X POST https://deploy.<YOUR_DOMAIN>/v1/update
```
