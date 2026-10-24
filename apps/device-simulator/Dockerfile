# ---------------------------------------------------------------------------
# Dockerfile = the recipe Docker follows to build an IMAGE.
# An image is a frozen package: a small Linux + Python + our code + libraries.
# A CONTAINER is a running copy of that image.
# Each instruction below creates a "layer". Docker caches layers, so steps
# that did not change are reused and the next build is much faster.
# ---------------------------------------------------------------------------

# FROM = the starting image. "python:3.12-slim" is Debian Linux with Python 3.12
# already installed. "slim" leaves out extras: smaller download, fewer security holes.
FROM python:3.12-slim

# ENV = environment variables inside the container.
# PYTHONDONTWRITEBYTECODE: don't create .pyc cache files (useless in a container).
# PYTHONUNBUFFERED: print logs right away, so `docker logs` / `kubectl logs` show them live.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# WORKDIR = "cd" into this folder (it is created if missing). Every command after this runs here.
WORKDIR /app

# Copy ONLY the requirements file first, then install the libraries.
# Why not copy everything at once? Caching: if requirements.txt did not change,
# Docker reuses this slow "pip install" layer even when our code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Now copy our code. A code change only re-runs the build from this line down.
COPY app ./app

# Never run as root in a container: if the app is hacked, the attacker is root.
# Create a normal user with a fixed number (UID). We use the NUMBER in USER because
# Kubernetes' "runAsNonRoot" check can only verify a numeric user.
RUN useradd --create-home --uid 10001 appuser
USER 10001

# EXPOSE is documentation: "this app listens on port 8000".
# It does NOT open the port. `docker run -p 8001:8000` or compose "ports:" does that.
EXPOSE 8000

# Docker checks the app every 15s. If /healthz fails 3 times, the container is "unhealthy".
# (Kubernetes ignores this line; there we use livenessProbe/readinessProbe instead.)
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz')" || exit 1

# CMD = the command that runs when the container starts.
# --host 0.0.0.0 means "accept connections from outside the container".
# (The default 127.0.0.1 would only accept connections from inside it.)
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
