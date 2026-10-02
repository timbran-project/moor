# Multi-stage build: Frontend build stage
FROM node:24-bookworm AS build
WORKDIR /app
ARG FLATBUFFERS_VERSION=25.9.23
# Build for the container's architecture; upstream Linux binaries are x86-64 only.
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git cmake g++ make && \
    curl -fsSL "https://github.com/google/flatbuffers/archive/refs/tags/v${FLATBUFFERS_VERSION}.tar.gz" -o /tmp/flatbuffers.tar.gz && \
    mkdir -p /tmp/flatbuffers && \
    tar -xzf /tmp/flatbuffers.tar.gz --strip-components=1 -C /tmp/flatbuffers && \
    cmake -S /tmp/flatbuffers -B /tmp/flatbuffers/build \
        -DCMAKE_BUILD_TYPE=Release -DFLATBUFFERS_BUILD_TESTS=OFF \
        -DFLATBUFFERS_BUILD_FLATLIB=OFF && \
    cmake --build /tmp/flatbuffers/build --target flatc --parallel 2 && \
    install -m 755 /tmp/flatbuffers/build/flatc /usr/local/bin/flatc && \
    flatc --version && \
    rm -rf /var/lib/apt/lists/* /tmp/flatbuffers /tmp/flatbuffers.tar.gz
COPY .git .git
RUN mkdir -p .git/objects
COPY package.json package-lock.json* ./
COPY clients/meadow clients/meadow
COPY clients/moor-web-mcp clients/moor-web-mcp
COPY clients/web-sdk clients/web-sdk
COPY crates/schema/schema crates/schema/schema
COPY tools/tsc.mjs tools/tsc.mjs
RUN npm ci
RUN npm run web:build

# nginx-based frontend image
FROM nginx:alpine AS frontend
COPY --from=build /app/clients/meadow/dist /usr/share/nginx/html
COPY clients/meadow/nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
