#!/bin/bash
# Script to fetch the cowbell core.
# This replaces the git submodule approach to allow independent development.

set -e

# Path to the cowbell directory relative to this script
COWBELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cowbell"
COWBELL_REPO="timbran-project/cowbell"
GITHUB_HOST="github.com"
COWBELL_REF="${COWBELL_REF:-moor-1.0-compatible}"

# Determine the protocol based on the current repository's 'origin' remote
# This helps use the same credentials/access method as the main repo.
CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "https")

if [[ "$CURRENT_REMOTE" == git@* ]] || [[ "$CURRENT_REMOTE" == ssh://* ]]; then
    REPO_URL="git@${GITHUB_HOST}:${COWBELL_REPO}.git"
else
    REPO_URL="https://${GITHUB_HOST}/${COWBELL_REPO}.git"
fi

if [ ! -d "$COWBELL_DIR" ]; then
    echo "Cloning cowbell from $REPO_URL at $COWBELL_REF..."
    git clone --branch "$COWBELL_REF" "$REPO_URL" "$COWBELL_DIR"
else
    echo "Cowbell directory already exists at $COWBELL_DIR"
    if [ -d "$COWBELL_DIR/.git" ]; then
        echo "Updating cowbell to $COWBELL_REF..."
        (cd "$COWBELL_DIR" && git fetch origin "$COWBELL_REF" && git checkout --detach FETCH_HEAD)
    else
        echo "Warning: $COWBELL_DIR exists but is not a git repository."
    fi
fi
