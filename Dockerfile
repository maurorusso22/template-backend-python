# Stage 1: build dependencies (uv + build tools stay here, not in final image)
FROM python:3.12.13-slim@sha256:804ddf3251a60bbf9c92e73b7566c40428d54d0e79d3428194edf40da6521286 AS builder

COPY --from=ghcr.io/astral-sh/uv:0.11.6@sha256:b1e699368d24c57cda93c338a57a8c5a119009ba809305cc8e86986d4a006754 /uv /uvx /bin/

WORKDIR /app

# Install production dependencies only (cached layer)
COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --no-install-project --frozen

# Copy application source
COPY src/ src/

# Stage 2: runtime (no uv/build tools — smaller image, smaller attack surface)
FROM python:3.12.13-slim@sha256:804ddf3251a60bbf9c92e73b7566c40428d54d0e79d3428194edf40da6521286 AS runtime

# NOTE if there are remaining OS vulnerabilities:
# `RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*`
# would patch them, but breaks reproducibility — the same Dockerfile built today
# and next week would produce different images depending on which Debian packages
# were available at build time. This conflicts with the digest pinning above,
# which exists precisely to guarantee deterministic builds.
# Preferred approach: let Dependabot/Renovate bump the base image digest via PR
# when a patched python:3.12.x-slim is published. That way upgrades are tracked,
# reviewed, and reproducible.

# No .pyc files (not useful in containers), unbuffered stdout/stderr for logging
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Explicit venv path — avoids relying on implicit .venv location
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

WORKDIR /app

# Non-root user for security (K8s runAsNonRoot: true)
RUN useradd --create-home --uid 1000 appuser

# Bring only the installed venv and source from builder, owned by appuser
COPY --from=builder --chown=appuser:appuser /app /app

USER appuser

EXPOSE 8000

# Let Docker (and orchestrators like Compose/ECS) check container health
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=2)"]

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
