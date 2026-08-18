# Multi-stage build: Frontend build stage
FROM node:20-bookworm AS build
WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends flatbuffers-compiler git && \
    rm -rf /var/lib/apt/lists/*
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
