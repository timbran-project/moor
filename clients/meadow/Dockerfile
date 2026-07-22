# Multi-stage build: Frontend build stage
FROM node:20-bookworm AS build
WORKDIR /app
# Install git for git hash lookup during build
RUN apt update && apt -y install git
COPY package.json package-lock.json* ./
# We need the moor repo side-by-side if we use file: dependency,
# or we just rely on the fact that we've already generated schemas if they are checked in.
# For a standalone repo, it's better to depend on the published package.
# But for now, let's assume we have everything we need.
RUN npm ci
COPY . .
RUN npm run build

# nginx-based frontend image
FROM nginx:alpine AS frontend
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
