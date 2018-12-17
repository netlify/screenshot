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

if [[ $BITBALLOON_GIT_REF == "" ]]; then
  echo "\$BITBALLOON_GIT_REF not provided"
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
BB_GCS_PATH="$GCS_BUCKET/bitballoon-k8s-artifacts/$BITBALLOON_GIT_REF"

# Prepare GCS auth
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
source ${HOME}/google-cloud-sdk/path.bash.inc
gcloud auth activate-service-account --key-file "${GCLOUD_SECRET_FILE}"

# Get docker image digest
IMAGE_DIGEST=$(gsutil cat $BB_GCS_PATH/image-digest)

# Prepare K8S manifest
gsutil cp -r $BB_GCS_PATH/templates/* .

# i.e.: gs://netlify-infrastructure/spinnaker-k8s-artifacts/gke/origin-poc/production/bitballoon/master
K8S_GS_PATH_BASE=$SPINNAKER_GCS_PATH/$K8S_PROVIDER/$K8S_CLUSTER/$K8S_ENV/bitballoon/$BITBALLOON_GIT_REF

# Get git info from the build being deployed
export BUILD_GIT_COMMIT=$(gsutil cat $BB_GCS_PATH/git-commit)
export BUILD_GIT_BRANCH=$(gsutil cat $BB_GCS_PATH/git-branch)

# Build manifests
suffix=$GIT_COMMIT.$(date +%s%N) # Different jobs may build the same commit SHA. Make the filenames different using a timestamp
for role in api web bg sidekiq; do
  export K8S_ROLE=$role
  jinja2_cmd <bitballoon.yml.j2 >deployment.$role.$suffix.yml

  if [[ ($role == "api" || $role == "web") && ($K8S_ENV == "production" || $K8S_ENV == "staging") ]]; then
    jinja2_cmd <balancer.yml.j2 >balancer.$role.$suffix.yml
  fi
done

# Upload manifests
for role in api web bg sidekiq; do
  gsutil cp deployment.$role.$suffix.yml $K8S_GS_PATH_BASE/

  if [[ ($role == "api" || $role == "web") && ($K8S_ENV == "production" || $K8S_ENV == "staging") ]]; then
    gsutil cp balancer.$role.$suffix.yml $K8S_GS_PATH_BASE/
  fi
done

echo "Generate spinnaker artifacts"
cat > spinnaker-artifacts.yml <<EOF
git_branch: $BUILD_GIT_BRANCH
git_commit: $BUILD_GIT_COMMIT
artifacts:
  - type: "docker/image"
    name: "gcr.io/netlify-services/bitballoon"
    reference: "$IMAGE_DIGEST"
  - type: gcs/object
    name: "deployment.api.yml"
    reference: "$K8S_GS_PATH_BASE/deployment.api.$suffix.yml"
  - type: gcs/object
    name: "balancer.api.yml"
    reference: "$K8S_GS_PATH_BASE/balancer.api.$suffix.yml"
  - type: gcs/object
    name: "deployment.web.yml"
    reference: "$K8S_GS_PATH_BASE/deployment.web.$suffix.yml"
  - type: gcs/object
    name: "balancer.web.yml"
    reference: "$K8S_GS_PATH_BASE/balancer.web.$suffix.yml"
  - type: gcs/object
    name: "deployment.bg.yml"
    reference: "$K8S_GS_PATH_BASE/deployment.bg.$suffix.yml"
  - type: gcs/object
    name: "deployment.sidekiq.yml"
    reference: "$K8S_GS_PATH_BASE/deployment.sidekiq.$suffix.yml"
EOF
