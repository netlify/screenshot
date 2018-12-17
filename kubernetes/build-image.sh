#!/bin/bash

: ${PROJECT_ID:="netlify-services"}
: ${CI:="false"}
: ${GIT_COMMIT:=$(git rev-parse HEAD)}

set -xe
set -o pipefail

# If we are building a PR, use the CHANGE_BRANCH value
if [[ -n "$CHANGE_BRANCH" ]]; then
  BRANCH_NAME=$CHANGE_BRANCH
fi

SCREENSHOT_NAME_SHA="gcr.io/$PROJECT_ID/screenshot:$GIT_COMMIT"
SCREENSHOT_NAME_BRANCH="gcr.io/$PROJECT_ID/screenshot:${BRANCH_NAME//\//-}"

# Build screenshot image
docker build -f kubernetes/docker/Dockerfile \
  -t $SCREENSHOT_NAME_SHA \
  .
