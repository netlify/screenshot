#!/bin/bash

: ${K8S_DEBUG:="false"}
: ${GIT_COMMIT:=$(git rev-parse HEAD)}
: ${K8S_NODEPOOL:="default"}

export K8S_DEBUG
export K8S_NODEPOOL
export K8S_ENV
export GIT_COMMIT

function jinja2_cmd() {
  python -c "import os;
import sys;
import jinja2;
loader=jinja2.FileSystemLoader('$PWD');
env = jinja2.Environment(loader=loader, undefined=jinja2.StrictUndefined);
sys.stdout.write(
    env.from_string(sys.stdin.read()).render(**os.environ)
)"
}

set -xe
set -o pipefail

if [[ $SCREENSHOT_GIT_REF == "" ]]; then
  echo "\$screenshot_GIT_REF not provided"
  exit 1
fi

if [[ $GCS_BUCKET == "" ]]; then
  echo "\$GCS_BUCKET not provided"
  exit 1
fi

if [[ $K8S_ENV == "" ]]; then
  echo "\$K8S_ENV not provided"
  exit 1
fi

if [[ $K8S_CLUSTER == "" ]]; then
  echo "\$K8S_CLUSTER not provided"
  exit 1
fi

if [[ $K8S_PROVIDER != "gke" && $K8S_PROVIDER != "eks" ]]; then
  echo "Invalid \$K8S_PROVIDER value ($K8S_PROVIDER). Supported values are: gke, eks"
  exit 1
fi

# Prepare paths
SPINNAKER_GCS_PATH="$GCS_BUCKET/spinnaker-k8s-artifacts"
BB_GCS_PATH="$GCS_BUCKET/screenshot-k8s-artifacts/$SCREENSHOT_GIT_REF"

# Prepare GCS auth
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
source ${HOME}/google-cloud-sdk/path.bash.inc
gcloud auth activate-service-account --key-file "${GCLOUD_SECRET_FILE}"

# Get docker image digest
IMAGE_DIGEST=$(gsutil cat $BB_GCS_PATH/image-digest)

# Prepare K8S manifest
gsutil cp -r $BB_GCS_PATH/templates/* .

# i.e.: gs://netlify-infrastructure/spinnaker-k8s-artifacts/gke/origin-poc/production/screenshot/master
K8S_GS_PATH_BASE=$SPINNAKER_GCS_PATH/$K8S_PROVIDER/$K8S_CLUSTER/$K8S_ENV/screenshot/$SCREENSHOT_GIT_REF

# Get git info from the build being deployed
export BUILD_GIT_COMMIT=$(gsutil cat $BB_GCS_PATH/git-commit)
export BUILD_GIT_BRANCH=$(gsutil cat $BB_GCS_PATH/git-branch)

# Build manifests
suffix=$GIT_COMMIT.$(date +%s%N) # Different jobs may build the same commit SHA. Make the filenames different using a timestamp
jinja2_cmd <screenshot.yml.j2 >deployment.$suffix.yml
jinja2_cmd <balancer.yml.j2 >balancer.$suffix.yml

# Upload manifests
gsutil cp deployment.$suffix.yml $K8S_GS_PATH_BASE/
gsutil cp balancer.$suffix.yml $K8S_GS_PATH_BASE/

echo "Generate spinnaker artifacts"
cat > spinnaker-artifacts.yml <<EOF
git_branch: $BUILD_GIT_BRANCH
git_commit: $BUILD_GIT_COMMIT
artifacts:
  - type: "docker/image"
    name: "gcr.io/netlify-services/screenshot"
    reference: "$IMAGE_DIGEST"
  - type: gcs/object
    name: "deployment.yml"
    reference: "$K8S_GS_PATH_BASE/deployment.$suffix.yml"
  - type: gcs/object
    name: "balancer.yml"
    reference: "$K8S_GS_PATH_BASE/balancer.$suffix.yml"
EOF
