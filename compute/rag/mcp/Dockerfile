FROM python:3.12-slim

# Hermes (and any other MCP client) talks to this server over streamable-http.
# Stdio is the dev/local transport; this image is for the streamable-http path.

RUN useradd -u 568 -m -s /bin/bash mcp && \
    apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Pin to the same major versions declared in server.py's PEP 723 header.
# Bump deliberately, in sync with that header.
RUN pip install --no-cache-dir \
    "mcp>=1.0,<2" \
    "httpx>=0.27,<1" \
    "qdrant-client>=1.13,<2"

COPY server.py /app/server.py

USER 568:568

# Streamable-HTTP defaults — the Custom App overrides via environment.
ENV MCP_TRANSPORT=streamable-http \
    MCP_HTTP_HOST=0.0.0.0 \
    MCP_HTTP_PORT=8080

EXPOSE 8080
CMD ["python", "/app/server.py"]
