# Multi-stage build: Frontend build stage
FROM node:20-bookworm AS build
WORKDIR /app
ARG FLATBUFFERS_VERSION=25.9.23
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git unzip && \
    curl -fsSL "https://github.com/google/flatbuffers/releases/download/v${FLATBUFFERS_VERSION}/Linux.flatc.binary.clang%2B%2B-18.zip" -o /tmp/flatc.zip && \
    unzip -q /tmp/flatc.zip -d /usr/local/bin && \
    chmod +x /usr/local/bin/flatc && \
    flatc --version && \
    rm -rf /var/lib/apt/lists/* /tmp/flatc.zip
COPY .git .git
RUN mkdir -p .git/objects
COPY package.json package-lock.json* ./
COPY clients/meadow clients/meadow
COPY clients/moor-web-mcp clients/moor-web-mcp
COPY clients/web-sdk clients/web-sdk
COPY crates/schema/schema crates/schema/schema
RUN npm ci
RUN npm run web:build

# nginx-based frontend image
FROM nginx:alpine AS frontend
COPY --from=build /app/clients/meadow/dist /usr/share/nginx/html
COPY clients/meadow/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
