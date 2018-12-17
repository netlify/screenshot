#!/bin/bash

: ${PROJECT_ID:="netlify-services"}
: ${CI:="false"}
: ${GIT_COMMIT:=$(git rev-parse HEAD)}
: ${GCS_BUCKET:="gs://netlify-infrastructure"}

# If we are building a PR, use the CHANGE_BRANCH value
if [[ -n "$CHANGE_BRANCH" ]]; then
  BRANCH_NAME=$CHANGE_BRANCH
fi

set -xe
set -o pipefail

SCREENSHOT_NAME_SHA="gcr.io/$PROJECT_ID/screenshot:$GIT_COMMIT"
SCREENSHOT_NAME_BRANCH="gcr.io/$PROJECT_ID/screenshot:${BRANCH_NAME//\//-}"

cleanup_images() {
  docker rmi $SCREENSHOT_NAME_SHA || true
  if [[ $BRANCH_NAME != "master" ]]; then
    docker rmi $SCREENSHOT_NAME_BRANCH || true
  fi
}
trap cleanup_images EXIT

export CLOUDSDK_CORE_DISABLE_PROMPTS=1
source ${HOME}/google-cloud-sdk/path.bash.inc
gcloud components install kubectl
gcloud auth activate-service-account --key-file "${GCLOUD_SECRET_FILE}"

# Prepare path
GCS_PATH="$GCS_BUCKET/screenshot-k8s-artifacts"

# Upload Docker image
docker tag $SCREENSHOT_NAME_SHA $SCREENSHOT_NAME_BRANCH
gcloud docker -- push $SCREENSHOT_NAME_SHA
gcloud docker -- push $SCREENSHOT_NAME_BRANCH

# Upload Docker image digest
DOCKER_IMAGE_DIGEST=$(gcloud container images describe $SCREENSHOT_NAME_SHA --format='value(image_summary.fully_qualified_digest)')
echo $DOCKER_IMAGE_DIGEST > image-digest
gsutil cp image-digest $GCS_PATH/$GIT_COMMIT/image-digest
gsutil cp image-digest $GCS_PATH/$BRANCH_NAME/image-digest

# Upload K8S templates
gsutil cp -r kubernetes/manifests/* $GCS_PATH/$GIT_COMMIT/templates/
gsutil cp -r kubernetes/manifests/* $GCS_PATH/$BRANCH_NAME/templates/

# Save git information
echo $BRANCH_NAME > git-branch
gsutil cp git-branch $GCS_PATH/$GIT_COMMIT/git-branch
gsutil cp git-branch $GCS_PATH/$BRANCH_NAME/git-branch
rm git-branch
echo $GIT_COMMIT > git-commit
gsutil cp git-commit $GCS_PATH/$GIT_COMMIT/git-commit
gsutil cp git-commit $GCS_PATH/$BRANCH_NAME/git-commit
rm git-commit
