# template-backend-python

A production-ready template for Python backend projects. Clone it, rename a few values, and start building — CI/CD pipeline, Docker, pre-commit hooks, and security scanning are already wired up.

## When to use this template

**Good fit:**

- REST APIs and HTTP microservices (FastAPI)
- Internal backend services behind an API gateway
- Lightweight CRUD services with JSON payloads

**Not a fit:**

- ML/data pipelines — different dependency story (torch, CUDA, notebooks), different CI shape
- Frontend or fullstack apps — no JS toolchain, no SSR, no asset pipeline
- CLI tools or libraries — this template assumes a long-running HTTP server with health checks
- Event-driven workers (Kafka, SQS consumers) — the Dockerfile and health check assume an HTTP endpoint; you would need to rework both

## What's included

| Component | What it does |
| --------- | ------------ |
| **FastAPI app** (`src/`) | Starter API with `/health`, `POST /items`, `GET /items/{id}`, Pydantic models, in-memory storage |
| **Tests** (`tests/`) | Pytest suite with coverage enforcement (≥80%) using `TestClient` / `httpx` |
| **Dockerfile** | Multi-stage build, digest-pinned base images, non-root user, `HEALTHCHECK`, no dev dependencies |
| **CI pipeline** (`.github/workflows/ci.yml`) | 4-job GitHub Actions workflow — quality checks, Dockerfile security (Hadolint + Trivy), Docker build + image scan + smoke test, registry push |
| **Pre-commit hooks** (`.pre-commit-config.yaml`) | Ruff (lint + format), mypy, trailing whitespace, large file guard, secret scanning (gitleaks), conventional commits |
| **Dependabot** (`.github/dependabot.yml`) | Automated weekly PRs for Docker base images, Python packages, and GitHub Actions versions |
| **PR template** (`.github/pull_request_template.md`) | Standardized what/why/how-to-test/checklist for every PR |
| **CODEOWNERS** (`.github/CODEOWNERS`) | Auto-assigns reviewers based on paths touched |
| **Internal docs submodule** (`docs-internal/`) | Git submodule pointing to a private repo for internal documentation |
| **uv** | Fast Python package manager — replaces pip/pip-tools, manages the lockfile (`uv.lock`) |
| **ruff** | Single tool replacing black (formatting), flake8 (linting), and isort (import sorting) |

## Setup: Starting a new project from this template

### 1. Create the repo

**Option A — GitHub UI:** Click **"Use this template"** → **"Create a new repository"** on the template's GitHub page.

**Option B — Manual clone:**

```bash
git clone https://github.com/<org>/template-backend-python.git my-service
cd my-service
rm -rf .git
git init && git add . && git commit -m "feat: init from template"
```

### 2. Rename the project

Search for `TODO` comments and update these values:

| File | What to change |
| ---- | -------------- |
| `pyproject.toml` | `name = "template-backend-python"` → your project name |
| `.github/workflows/ci.yml` | `APP_NAME` and `DOCKER_IMAGE_NAME` env vars |
| `src/main.py` | `FastAPI(title="Template Backend Python")` → your project name |

The template ships with a `docs-internal/` submodule pointing to the original docs repo. Replace it with your own:

```bash
# Remove the template's submodule
git rm docs-internal
rm -rf .git/modules/docs-internal

# Add your team's internal docs repo
git submodule add https://github.com/<your-org>/docs-internal.git docs-internal
```

See [Internal documentation (submodule)](#internal-documentation-submodule) for more details.

### 3. Install and verify

```bash
# Install all dependencies (including dev tools and pre-commit)
uv sync --all-extras

# Install pre-commit git hooks (pre-commit itself is already installed by the step above)
uv run pre-commit install
uv run pre-commit install --hook-type commit-msg

# Run the quality checks
uv run ruff format --check .
uv run ruff check .
uv run mypy src/
uv run pytest --cov=src --cov-fail-under=80
```

To run the CI pipeline locally with `act`, see [Running locally with `act`](#running-locally-with-act) — you'll need to create a `.secrets` file first.

### 4. Push to GitHub and configure

1. Push your branch and open a PR to `main`.
2. Wait for the first CI run to complete green.
3. **Then** configure branch protection on `main` (see [Branch protection](#branch-protection-on-main) below) — the "Require status checks" dropdown is only populated after the workflow has run at least once.
4. Configure registry secrets for the push job (see [Registry configuration](#registry-configuration)).

## Branch protection on `main`

> **Important:** GitHub does not carry branch protection rules across template copies. You must configure this on every repo created from this template.

> **Ordering:** Configure protection **after** the first CI run completes green. The "Require status checks to pass" dropdown is populated from historical workflow runs — checks that have never executed are not selectable.

Go to **Settings → Branches → Add branch protection rule**, set branch name pattern to `main`, and enable:

| Rule | Why |
| ---- | --- |
| Require a pull request before merging | No direct pushes to `main` |
| Require approvals (≥1) | At least one reviewer signs off |
| Require status checks to pass before merging | Select `quality`, `dockerfile-security`, `build` |
| Require branches to be up to date before merging | Prevents two independently-green PRs from breaking `main` when combined |
| Do not allow force pushes | Protects commit history |
| Do not allow deletions | Prevents accidental branch deletion |
| Require linear history | Forces squash or rebase merges — clean `git log --oneline` |

The `push` job runs only on `main` (not on PRs), so it will not appear in the status checks dropdown — this is expected.

## How to customize

**Add a new endpoint:** Create your route in `src/main.py` (or split into a new router module), add Pydantic models in `src/models.py`, and add tests in `tests/`. Coverage must stay ≥80%.

**Add a database:** Add your driver (e.g. `asyncpg`, `sqlalchemy`) to `[project.dependencies]` in `pyproject.toml`, run `uv sync`. Update the Dockerfile if you need system libraries (`libpq-dev`, etc.) — add `apt-get install` in the builder stage and copy the resulting libs to the runtime stage.

**Change Python version:** Update in three places:
1. `pyproject.toml` — `requires-python`
2. `.github/workflows/ci.yml` — `PYTHON_VERSION` env var
3. `Dockerfile` — both `FROM python:` lines (update the tag and digest)

**Adjust coverage threshold:** Change `--cov-fail-under=80` in `ci.yml` (step `tests`) and in your local test commands.

**Add lint rules:** Edit `[tool.ruff.lint] select` in `pyproject.toml`. See the [ruff rule index](https://docs.astral.sh/ruff/rules/) for available codes.

**Change Trivy severity gate:** Edit `--severity` in the Trivy steps in `ci.yml`. Default is `CRITICAL,HIGH`. Add `MEDIUM` for stricter scanning.

## CI pipeline: what it does, job by job

The pipeline runs on every push to `main` and every PR against `main`. It is defined in `.github/workflows/ci.yml`.

### Job 1: `quality` — Code Quality & Testing

Runs format check, linting, type checking, and tests in a **fail-fast cascade** — each step is gated on the previous step's success, so the pipeline stops at the first failure.

| Step | Command | What it checks |
| ---- | ------- | -------------- |
| Format | `ruff format --check .` | Code formatting (replaces black) |
| Lint | `ruff check .` | Linting + import sorting (replaces flake8 + isort) |
| Type check | `mypy src/` | Static type analysis |
| Tests | `pytest --cov=src --cov-fail-under=80` | Unit tests with ≥80% coverage gate |

### Job 2: `dockerfile-security` — Dockerfile Static Analysis

Runs after `quality` passes. Scans the Dockerfile and repo configs without touching the Docker daemon.

- **Hadolint** — Dockerfile best-practice linter. Error-level findings fail the build; warnings surface in SARIF only.
- **Trivy config scan** — Catches misconfigurations in Dockerfile and YAML files. CRITICAL/HIGH findings fail the build.

Both tools upload SARIF results to the GitHub **Security → Code scanning** tab (on GitHub only, skipped under `act`).

### Job 3: `build` — Docker Build & Image Security

Runs after `quality` and `dockerfile-security` both pass. Builds the Docker image, scans it, and smoke-tests it.

1. **Build** — Multi-stage Docker build with BuildKit. Uses GHA cache on GitHub, no cache under `act`.
2. **Trivy image scan** — Scans the built image for CVEs. CRITICAL/HIGH with a known fix fail the build (unfixed CVEs are ignored). CVEs listed in `.trivyignore` with an `exp:YYYY-MM-DD` date are temporarily accepted.
3. **Smoke test** — Starts the container, waits for readiness, then validates `GET /health`, `POST /items`, and `GET /items/{id}` round-trip. Fails if any response is unexpected.
4. **Artifact handoff** — On `main` only, saves the image as a tar artifact for the push job.

### Job 4: `push` — Push to Registry

Runs only on push to `main` (skipped on PRs). Loads the exact image that was scanned and smoke-tested — no rebuild.

1. Verifies registry credentials are configured (hard-fails with a clear error if missing).
2. Loads the image artifact from Job 3.
3. Logs in to the configured registry.
4. Tags with the commit SHA and pushes.

Under `act`, the job starts but every step is skipped (registry push is a GitHub-only side effect).

### What runs where

| | GitHub | `act` (local) |
| - | ------ | ------------- |
| Quality checks, lint, tests | Yes | Yes |
| Hadolint + Trivy config scan | Yes | Yes |
| Docker build + image scan + smoke test | Yes | Yes |
| SARIF uploads (Security tab) | Yes | Skipped |
| Coverage artifact upload | Yes | Skipped |
| Registry push | Yes (main only) | Skipped |

## Registry configuration

The pipeline is registry-agnostic. It uses three configurable values:

| Type | Name | Where to set |
| ---- | ---- | ------------ |
| Secret | `REGISTRY_USERNAME` | Repo → Settings → Secrets → Actions |
| Secret | `REGISTRY_TOKEN` | Repo → Settings → Secrets → Actions |
| Variable | `REGISTRY_URL` | Repo → Settings → Variables → Actions |

Images are tagged with the commit SHA only. `latest` is intentionally avoided — it causes non-deterministic rollbacks, cache inconsistency across nodes, and no traceability to a specific commit.

### Per-registry setup

**GitHub Container Registry (ghcr.io):**

| Name | Value |
| ---- | ----- |
| `REGISTRY_USERNAME` | Your GitHub username |
| `REGISTRY_TOKEN` | Classic PAT with `write:packages`, `read:packages` (fine-grained tokens don't support GHCR yet) |
| `REGISTRY_URL` | `ghcr.io/<your-username>` |

Result: `ghcr.io/<username>/<DOCKER_IMAGE_NAME>:<sha>`

**Docker Hub:**

| Name | Value |
| ---- | ----- |
| `REGISTRY_USERNAME` | Docker Hub username |
| `REGISTRY_TOKEN` | Access token (Hub → Account Settings → Security) |
| `REGISTRY_URL` | *(leave empty)* — defaults to Docker Hub |

Result: `<DOCKER_IMAGE_NAME>:<sha>`

**AWS ECR:**

| Name | Value |
| ---- | ----- |
| `REGISTRY_USERNAME` | `AWS` |
| `REGISTRY_TOKEN` | Output of `aws ecr get-login-password` (short-lived — prefer OIDC, see below) |
| `REGISTRY_URL` | `<account-id>.dkr.ecr.<region>.amazonaws.com` |

For production ECR, replace the `docker/login-action` step with the [`aws-actions/amazon-ecr-login`](https://github.com/aws-actions/amazon-ecr-login) action using OIDC federation — no long-lived credentials needed.

**Azure Container Registry (ACR):**

| Name | Value |
| ---- | ----- |
| `REGISTRY_USERNAME` | Service principal app ID or admin username |
| `REGISTRY_TOKEN` | Service principal password or admin password |
| `REGISTRY_URL` | `<registry-name>.azurecr.io` |

**Harbor / Nexus / Artifactory (self-hosted):**

| Name | Value |
| ---- | ----- |
| `REGISTRY_USERNAME` | Registry username |
| `REGISTRY_TOKEN` | Registry password or token |
| `REGISTRY_URL` | `registry.example.com` (your instance hostname) |

## Internal documentation (submodule)

The `docs-internal/` directory is a git submodule pointing to a private repository for internal documentation (not client-facing). It is **not** fetched automatically by `git clone` — you need an extra step.

**Initialize after cloning:**

```bash
# If you already cloned without --recurse-submodules:
git submodule update --init

# Or clone with submodules in one step:
git clone --recurse-submodules <repo-url>
```

**Update to latest:**

```bash
cd docs-internal && git pull origin main && cd ..
git add docs-internal
git commit -m "chore: update docs-internal submodule"
```

**Access:** Requires read access to the private `docs-internal` repo (SSH key or PAT). If you don't have access, the submodule init will fail — the rest of the template works fine without it.

## Running locally with `act`

[`act`](https://github.com/nektos/act) runs the GitHub Actions pipeline locally using Docker. This lets you catch failures before pushing.

### Prerequisites

- Docker running
- `act` installed (`brew install act` on macOS)
- A `GITHUB_TOKEN` — several composite actions in the pipeline need it to fetch install scripts. On GitHub this is auto-provisioned; under `act` you must supply it.

### One-time setup

Create a `.secrets` file at the repo root. The format is one `KEY=value` pair per line:

```
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

If you have the GitHub CLI installed, you can generate it in one step:

```bash
echo "GITHUB_TOKEN=$(gh auth token)" > .secrets
```

The `.secrets` file is gitignored. **Do not commit it** — the token grants API access to repos your `gh` session can see. If a run fails with `401 Bad credentials`, re-run `gh auth login` and regenerate the file.

### Running

```bash
# Run the full pipeline (simulates a push to main)
act push --container-architecture linux/amd64 --secret-file .secrets

# Run a single job
act -j quality --secret-file .secrets
act -j build --secret-file .secrets

# Run PR-triggered jobs only
act pull_request --container-architecture linux/amd64 --secret-file .secrets
```

### What gets skipped locally

Steps guarded by `!env.ACT` are skipped under `act`:

- SARIF uploads to GitHub Security tab
- Coverage artifact upload
- Docker image artifact handoff between jobs
- Registry login and push

Everything else — quality checks, Dockerfile scanning, Docker build, Trivy image scan, smoke test — runs locally the same as on GitHub.

## Pre-commit hooks

Hooks run automatically on every commit (and on commit messages). `pre-commit` is included as a dev dependency in `pyproject.toml`, so it's already installed after `uv sync --all-extras`. You just need to register the git hooks once:

```bash
uv run pre-commit install
uv run pre-commit install --hook-type commit-msg
```

Run all hooks manually against the entire codebase:

```bash
uv run pre-commit run --all-files
```

### Installed hooks

| Hook | Source | What it does |
| ---- | ------ | ------------ |
| `trailing-whitespace` | pre-commit-hooks | Strips trailing whitespace |
| `end-of-file-fixer` | pre-commit-hooks | Ensures files end with a newline |
| `check-yaml` | pre-commit-hooks | Validates YAML syntax |
| `check-json` | pre-commit-hooks | Validates JSON syntax |
| `check-added-large-files` | pre-commit-hooks | Blocks files >500KB |
| `check-merge-conflict` | pre-commit-hooks | Detects unresolved merge conflict markers |
| `debug-statements` | pre-commit-hooks | Catches leftover `breakpoint()` / `pdb` |
| `ruff` | ruff-pre-commit | Linting + import sorting (auto-fixes) |
| `ruff-format` | ruff-pre-commit | Code formatting |
| `mypy` | mirrors-mypy | Static type checking |
| `gitleaks` | gitleaks | Secret scanning (API keys, tokens, `.env` values) |
| `conventional-pre-commit` | compilerla | Enforces conventional commit messages |

### Conventional commits

Commit messages must follow the format `<type>: <description>`. Allowed types:

`feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `build`

Examples:

```
feat: add user authentication endpoint
fix: handle empty payload on POST /items
docs: update registry configuration in README
ci: bump trivy action to v0.69.3
```

A commit with a non-conforming message (e.g., `add new feature`) will be rejected by the `commit-msg` hook.

## Design decisions

**Why uv over pip/pip-tools:** 10-100x faster installs, built-in lockfile (`uv.lock`), deterministic resolution, and a single tool for Python version management + dependency install + virtual env creation. Replaces pip, pip-tools, pyenv, and virtualenv.

**Why ruff over black + flake8 + isort:** One Rust-based tool replaces three Python tools. 10-100x faster, single config block in `pyproject.toml`, one version to pin and update. Same rule coverage via rule selectors (`E`, `F`, `I`, `W`, `UP`, `B`, `SIM`).

**Why fail-fast cascade in CI:** Each quality step is gated on the previous step's success (`if: steps.<prev>.outcome == 'success'`). A formatting error stops the pipeline immediately instead of also running lint, type check, and tests — less noise, faster feedback.

**Why digest-pinned Docker base images:** Human-readable tags like `python:3.12-slim` are mutable — the image behind the tag changes when Debian pushes security patches. Pinning the digest (`@sha256:...`) guarantees the exact same image on every build. Dependabot opens PRs when a new digest is available, so updates are tracked and reviewed.

**Why non-root container user:** Running as root inside a container means a container escape gives the attacker root on the host. The `appuser` (UID 1000) follows the principle of least privilege and satisfies Kubernetes `runAsNonRoot: true` policies.

**Why push exact bytes (no rebuild):** The `build` job saves the image as a tar artifact after scanning and smoke-testing it. The `push` job loads and pushes those exact bytes. A rebuild from cache could silently diverge — different layer timestamps, different package versions if a mirror updated between runs. Push-what-you-scanned eliminates that class of inconsistency.

**Why commit SHA tags (no `latest`):** `latest` is non-deterministic — two nodes pulling `latest` minutes apart can get different images. Rollbacks become guesswork ("which `latest` was it?"). SHA tags trace every running container back to the exact commit that produced it.

**Why `.trivyignore` with expiration dates:** Sometimes a CVE has a fix upstream but the Docker base image hasn't been rebuilt yet. Ignoring it permanently is dangerous; failing CI on something you can't fix yet is wasteful. The `exp:YYYY-MM-DD` directive auto-expires the exception so Trivy resumes flagging it after the grace period.
