FROM python:3.11-slim

# Add ARG for environment (defaults to dev)
ARG ENVIRONMENT=dev

ENV PYTHONUNBUFFERED=1
ENV DAGSTER_HOME=/opt/dagster/dagster_home
ENV DAGSTER_ENVIRONMENT=${ENVIRONMENT}

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    gdal-bin \
    libgdal-dev \
    g++ \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Create Dagster home directory
RUN mkdir -p $DAGSTER_HOME

# Copy application files
WORKDIR /app
COPY . .

# Install uv and use it to install dependencies
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && export PATH="/root/.local/bin:$PATH" \
    && uv venv \
    && uv pip install --system -e .[dev]
    
# Copy Dagster instance YAML configuration
COPY deployment/environments/${ENVIRONMENT}/dagster.yaml $DAGSTER_HOME/dagster.yaml

# Copy and set up entrypoint script BEFORE changing user
COPY deployment/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create a non-root user and switch to it (moved after chmod)
RUN useradd -m dagster && \
    chown -R dagster:dagster $DAGSTER_HOME /app
USER dagster

# Expose port for Dagster webserver
EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]