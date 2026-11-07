# ---- build stage: wheels compile (gcc wagairah final image mein nahi jaate) ----
FROM python:3.12-slim AS build
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- runtime stage ----
FROM python:3.12-slim
# OS packages ke security patches (Trivy gate HIGH/CRITICAL pe fail karta hai)
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY --from=build /install /usr/local
WORKDIR /app
COPY app/ ./app/
COPY sample-docs/ ./sample-docs/

# Non-root (PSA restricted + Kyverno). Numeric UID taaki runAsNonRoot verify ho sake.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

# readOnlyRootFilesystem: Python ko writable HOME/tmp chahiye → /tmp emptyDir (Helm chart mount karta hai)
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 HOME=/tmp
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]
