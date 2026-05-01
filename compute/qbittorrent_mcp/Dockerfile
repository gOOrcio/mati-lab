FROM python:3.12-slim

# qBittorrent MCP server — wraps the qBit Web API in MCP tool calls.
# Mirror of compute/rag/mcp/Dockerfile shape.

RUN useradd -u 568 -m -s /bin/bash mcp && \
    apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN pip install --no-cache-dir \
    "mcp>=1.0,<2" \
    "httpx>=0.27,<1" \
    "uvicorn[standard]>=0.30,<1"

COPY server.py /app/server.py

USER 568:568

ENV MCP_TRANSPORT=streamable-http \
    MCP_HTTP_HOST=0.0.0.0 \
    MCP_HTTP_PORT=8080

EXPOSE 8080
CMD ["python", "/app/server.py"]
