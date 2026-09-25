#!/bin/bash
# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
# software: you can redistribute it and/or modify it under the terms of the GNU
# Affero General Public License as published by the Free Software Foundation,
# version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

# Test script for web-ssl deployment
# Note: This test cannot verify actual SSL certificates without a real domain
# It validates that services start and nginx is properly configured

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common helpers
source "$SCRIPT_DIR/../../test-helpers.sh"

log_info "Starting web-ssl deployment test"
log_warn "Note: SSL certificate validation requires a real domain and is skipped in automated tests"

# Change to the deployment directory
cd "$SCRIPT_DIR"

# Setup test environment (clean up any existing containers)
setup

# Check if .env file exists
if [ ! -f .env ]; then
    log_warn "No .env file found - creating test .env"
    cat > .env << EOF
VIRTUAL_HOST=localhost
LETSENCRYPT_HOST=localhost
LETSENCRYPT_EMAIL=test@example.com
EOF
fi

# Start services (without certbot)
log_info "Starting services with docker compose..."
docker compose up -d

# Wait for services to start
wait_for_service "moor-daemon" 30
wait_for_service "moor-web-host" 30
wait_for_service "moor-frontend" 30

# Wait for database import to complete
wait_for_import "moor-daemon" 180

# Wait for HTTP port to be available
wait_for_port "localhost" 80 30

# This job checks startup without certificates. HTTPS routing and certificate
# validation require a separate test with configured certificates.
log_info "Service startup verified; HTTPS was not tested"

# Check docker logs for errors
log_info "Checking docker logs for critical errors..."
for service in moor-daemon moor-web-host moor-frontend; do
    log_info "Checking $service logs..."
    ERRORS=$(docker compose logs "$service" 2>&1 | grep -iE "panic|fatal|error" | head -5)
    if [ -n "$ERRORS" ]; then
        log_warn "Found errors in $service logs:"
        echo "$ERRORS"
    else
        log_info "No critical errors in $service"
    fi
done

log_info "✓ Web-ssl startup smoke completed successfully"
log_info "Note: For full SSL validation, deploy on a server with a real domain and DNS"
