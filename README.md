# waffle-scaling-ai-infra
AI Infrastructure Using CI/CD to explore new infra automation.

# AI Sentiment + Speechify TTS Demo

A developer-friendly demo that analyzes message sentiment (HuggingFace) and speaks bot replies using Speechify TTS. Ships locally with Docker Compose and to AWS with Terraform/ECS. Includes Spacelift + Terragrunt wiring so platform teams can run plans from the `main` branch.

> **Note**: This is a demo. For production, you’d move Redis to ElastiCache, add HTTPS (ACM), secrets management, autoscaling, observability, and CI/CD.

---

## Table of Contents
- [Architecture](#architecture)
- [Repository Layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
- [Application Notes](#application-notes)
- [Cloud Reference (AWS Terraform)](#cloud-reference-aws-terraform)
- [Spacelift + Terragrunt](#spacelift--terragrunt)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [License \u0026 Contributing](#license--contributing)

---

## Architecture

```
[Browser] ──HTTP──> [ALB:80] ──> [ECS Fargate Task]
                               ├─ api (Flask :5000)
                               ├─ tts (Node :3000)
                               └─ redis (6379)
```

- Flask’s `/predict` does sentiment and caches in Redis.
- Flask’s `/speak` proxies text to the Node TTS (Speechify) service and streams MP3.
- **Intra-task networking** can vary. If `localhost` between containers is unreliable in your environment, prefer ECS Service Connect/Cloud Map or run TTS inside the API container for the demo.

---

## Repository Layout

```
<repo-root>/
├─ api/                    # Flask app + HTML UI
│  ├─ app.py               # routes (/ , /predict, /speak, /metrics)
│  ├─ speechify.py         # tiny proxy helper to TTS service
│  ├─ requirements.txt
│  └─ Dockerfile
├─ tts/                    # Node Speechify TTS service
│  ├─ tts-server.mjs
│  ├─ package.json
│  └─ Dockerfile
├─ terraform/              # reference AWS infra (ALB, ECS, VPC, ECR)
│  ├─ providers.tf  locals.tf  variables.tf  outputs.tf  main.tf
│  ├─ vpc.tf  alb.tf  ecr.tf  ecs.tf
├─ infra/                  # Terragrunt entry + sample unit
│  ├─ terragrunt.hcl       # root config
│  ├─ shared/main.tf       # small local module (no cloud creds needed)
│  └─ dev/terragrunt.hcl   # points to ../shared
├─ .spacelift/
│  └─ config.yml           # set project_root=infra and non-interactive args
├─ docker-compose.yml      # local dev bring-up
└─ README.md               # this file
```

---

## Prerequisites

- Docker Desktop (or equivalent)
- Python 3.11+, Node 20+
- Git + GitHub account
- **Speechify API key** for TTS
- Optional for cloud: AWS account/CLI, Terraform ≥ 1.6, Spacelift (if using)

### GitHub SSH Setup (macOS quick path)

```bash
ssh-keygen -t ed25519 -C "<your-github-email>"
# Press Enter for ~/.ssh/id_ed25519; set a passphrase if desired

eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain ~/.ssh/id_ed25519 2>/dev/null || ssh-add -K ~/.ssh/id_ed25519
pbcopy < ~/.ssh/id_ed25519.pub  # paste in GitHub → Settings → SSH and GPG keys
```

Switch your remote to SSH:

```bash
git remote set-url origin git@github.com:<you>/<repo>.git
```

---

## Local Development

### Environment

Create `.env` at repo root (used by Docker Compose to pass secrets to `tts`):

```
SPEECHIFY_API_KEY=sk_live_XXXXXXXXXXXXXXXX
```

### Docker Compose

Example `docker-compose.yml`:

```yaml
version: "3.9"
services:
  web:
    build: ./api
    ports:
      - "5000:5000"
    environment:
      REDIS_HOST: redis
      REDIS_PORT: 6379
      SPEECHIFY_TTS_URL: http://tts:3000/tts
    depends_on:
      - redis
      - tts

  tts:
    build: ./tts
    environment:
      SPEECHIFY_API_KEY: ${SPEECHIFY_API_KEY}

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

Bring it up:

```bash
docker compose up --build
open http://localhost:5000
```

Send a chat message, then click **🔊 Speak** on bot replies.

---

## Application Notes

**API (Flask)**
- `/` serves the chat UI.
- `/predict` POST `{text}` → returns sentiment (cached in Redis for 1h).
- `/speak` POST `{text, voiceId?}` → streams MP3 by proxying to TTS service.
- Env: `REDIS_HOST`, `REDIS_PORT`, `SPEECHIFY_TTS_URL`.

**TTS (Node)**
- POST `/tts` `{text, voiceId, format}` → `audio/mpeg` bytes.
- Env: `SPEECHIFY_API_KEY` (keep server-side only).

**Redis**
- Ephemeral cache for faster repeat predictions.

---

## Cloud Reference (AWS Terraform)

The provided Terraform under `terraform/` is a **reference** for a public demo: VPC (public subnets), ALB, ECS cluster/service, CloudWatch Logs, and two ECR repos. Adjust for your standards before production.

### One-time Infra

```bash
cd terraform
terraform init
terraform apply -auto-approve \
  -var 'project_name=ai-sentiment-tts-demo' \
  -var 'region=us-west-2' \
  -var 'speechify_api_key=sk_live_XXXXXXXXXXXXXXXX'
```

Copy the outputs: `ecr_api_repo_url`, `ecr_tts_repo_url`, `app_url`.

### Build & Push Images

```bash
# Login to ECR (example region)
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin <acct>.dkr.ecr.us-west-2.amazonaws.com

# API
docker build -t api ./api
docker tag api:latest <ecr_api_repo_url>:v1
docker push <ecr_api_repo_url>:v1

# TTS
docker build -t tts ./tts
docker tag tts:latest <ecr_tts_repo_url>:v1
docker push <ecr_tts_repo_url>:v1
```

Update the service to use those images:

```bash
terraform apply -auto-approve \
  -var 'app_image=<ecr_api_repo_url>:v1' \
  -var 'tts_image=<ecr_tts_repo_url>:v1' \
  -var 'speechify_api_key=sk_live_XXXXXXXXXXXXXXXX'
```

Open the app:

```bash
open $(terraform output -raw app_url)
```

> **Intra-task networking**: If `SPEECHIFY_TTS_URL=http://localhost:3000/tts` or `REDIS_HOST=localhost` fails in your environment, use ECS **Service Connect** or Cloud Map or consolidate TTS into the API container for demo simplicity.

---

## Spacelift + Terragrunt

### Terragrunt Files

```
infra/
├─ terragrunt.hcl            # root config
├─ shared/main.tf            # local module (no cloud creds needed)
└─ dev/terragrunt.hcl        # points to ../shared
```

**`infra/shared/main.tf`**

```hcl
terraform {
  required_providers {
    random = { source = "hashicorp/random" }
    local  = { source = "hashicorp/local" }
  }
}

resource "random_pet" "name" { length = 2 }

resource "local_file" "demo" {
  filename = "demo-output.txt"
  content  = "hello from ${random_pet.name.id}"
}

output "demo_message" { value = local_file.demo.content }
```

**`infra/terragrunt.hcl`**

```hcl
locals { project = "waffle-scaling-ai-infra" }

generate "provider" {
  path      = "provider_generated.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform { required_version = ">= 1.5.0" }
EOF
}
```

**`infra/dev/terragrunt.hcl`**

```hcl
terraform { source = "../shared" }
inputs = { env = "dev" }
```

### Spacelift Runtime Config

Create **`.spacelift/config.yml`** at repo root:

```yaml
version: 2
stack_defaults:
  project_root: infra
  environment:
    TG_CLI_ARGS_init: "--terragrunt-non-interactive"
    TG_CLI_ARGS_plan: "--terragrunt-non-interactive"
    TG_CLI_ARGS_apply: "--terragrunt-non-interactive"
  before_init:
    - terragrunt --version
```

### Create the Stack

- **Vendor**: Terragrunt
- **Repository**: this repo; **Branch**: `main`
- **Project root**: `infra` (or rely on `config.yml`)
- Tool: OpenTofu or Terraform (pin version)
- Trigger a run → review plan → **Confirm** apply. You should see `random_pet` + `local_file` created and an output `demo_message`.

---

## Troubleshooting

- **Git push prompts for password**: switch remote to SSH or use a PAT.
- **`/speak` returns 502**: verify TTS service is up and `SPEECHIFY_API_KEY` is set; check logs.
- **Speechify 401/403**: confirm key, environment, and that you aren’t exposing it in the browser.
- **ECS task can’t reach Redis/TTS**: prefer Service Connect or place both in one container image for demo.
- **Spacelift doesn’t find `infra/`**: ensure `.spacelift/config.yml` is at repo root.

---

## Roadmap

- HTTPS (ACM) + domain in Route53
- Replace Redis container with ElastiCache
- Service Connect/Cloud Map for container service discovery
- GitHub Actions CI: build/test → push images → trigger Spacelift run
- Observability: CloudWatch dashboards + structured logs; optional Prometheus/Grafana
- Feature: voice selector in UI; volume/speed controls; SSML support

---

## License & Contributing

- License: MIT (or your org’s standard)
- PRs welcome — include clear repro steps and logs for any bugs.
