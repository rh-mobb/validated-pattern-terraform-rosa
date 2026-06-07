# --- STEP 1: Builder stage (Utilizes standard hardened Python base) ---
# Replace REGISTRY_PREFIX at build time via sed in run-pipeline.sh or use fully qualified URLs from ECR.
ARG REGISTRY_PREFIX
FROM ${REGISTRY_PREFIX}/hummingbird/python:3.14.5-fips-builder AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/app/deps -r requirements.txt

# --- STEP 2: Production stage (Utilizes absolute minimal distroless runtime) ---
FROM ${REGISTRY_PREFIX}/hummingbird/python:3.14.5
WORKDIR /app

COPY --from=builder /app/deps /app/deps
COPY app.py .

ENV PYTHONPATH=/app/deps/lib/python3.14/site-packages
ENV PATH=/app/deps/bin:$PATH
EXPOSE 8080

# MANDATORY: JSON Array Exec Form (No shell is present)
ENTRYPOINT ["gunicorn", "--bind", "0.0.0.0:8080", "app:app"]
