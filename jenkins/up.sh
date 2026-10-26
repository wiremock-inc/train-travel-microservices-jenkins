#!/usr/bin/env bash
# Boots Jenkins in Docker with the WireMock Cloud plugin and a 'train-travel' job that builds this repo's Jenkinsfile.
#   jenkins/up.sh           build the image and (re)start Jenkins
#   jenkins/up.sh --fresh   also discard the previous Jenkins home (build history)
#
# Settings, from the environment or jenkins/.env:
#   WIREMOCK_API_TOKEN      required: the WireMock Cloud API token builds use
#   WIREMOCK_API_ENDPOINT   default https://api.wiremock.cloud
#   JENKINS_PORT            default 8080
#   TRAIN_TRAVEL_BRANCH     the branch the job builds, default the current one. Jenkins clones it from GitHub.
#   PLUGIN_VERSION          the plugin release to install, e.g. 0.1.0, default the latest
#   WIREMOCK_PLUGIN_HPI     install this .hpi instead of a release
#   WIREMOCK_CLI_JAR        the CLI JAR to install. By default it's built once from WIREMOCK_CLI_SRC (default
#                           ../.worktrees/environments/wiremock-cli), as no CLI release on npm has the features the
#                           plugin needs yet. Delete jenkins/.build/wiremock to build it again.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$DIR")"
BUILD="$DIR/.build"
NAME=train-travel-jenkins

if [ -f "$DIR/.env" ]; then
  set -a
  . "$DIR/.env"
  set +a
fi
: "${WIREMOCK_API_TOKEN:?Set WIREMOCK_API_TOKEN, or put it in jenkins/.env (see jenkins/.env.example)}"
JENKINS_PORT="${JENKINS_PORT:-8080}"
TRAIN_TRAVEL_BRANCH="${TRAIN_TRAVEL_BRANCH:-$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)}"
mkdir -p "$BUILD"

# The plugin. Its repository is internal, so gh must be logged in with access to wiremock-inc.
rm -f "$BUILD"/*.hpi
if [ -n "${WIREMOCK_PLUGIN_HPI:-}" ]; then
  cp "$WIREMOCK_PLUGIN_HPI" "$BUILD/wiremock-cloud.hpi"
else
  gh release download ${PLUGIN_VERSION:+"v$PLUGIN_VERSION"} -R wiremock-inc/wiremock-cloud-jenkins-plugin \
    -p 'wiremock-cloud-*.hpi' -D "$BUILD"
  mv "$BUILD"/wiremock-cloud-*.hpi "$BUILD/wiremock-cloud.hpi"
fi
plugin_version="$(unzip -p "$BUILD/wiremock-cloud.hpi" META-INF/MANIFEST.MF | sed -n 's/^Plugin-Version: *//p' | tr -d '\r')"
echo "WireMock Cloud plugin $plugin_version"

# The CLI
if [ -n "${WIREMOCK_CLI_JAR:-}" ]; then
  cp "$WIREMOCK_CLI_JAR" "$BUILD/wiremock"
elif [ ! -f "$BUILD/wiremock" ]; then
  src="${WIREMOCK_CLI_SRC:-$REPO_DIR/../.worktrees/environments/wiremock-cli}"
  echo "Building the WireMock CLI from $src"
  # VERSION is deliberately unset: the JAR then reports version "local", which the plugin's minimum-version check allows.
  # No build cache: a cache shared with other checkouts can hand back outputs built from other code.
  (cd "$src" && ./gradlew --quiet --no-daemon --no-build-cache :app:bootJar)
  cp "$src/build/child-projects/app/libs/wiremock" "$BUILD/wiremock"
fi

if ! git -C "$REPO_DIR" ls-remote --exit-code --heads origin "$TRAIN_TRAVEL_BRANCH" >/dev/null; then
  echo "Warning: branch $TRAIN_TRAVEL_BRANCH isn't on GitHub, so the job won't find it until it's pushed" >&2
fi

docker build -t "$NAME" --build-arg PLUGIN_VERSION="$plugin_version" "$DIR"
docker rm -f "$NAME" >/dev/null 2>&1 || true
if [ "${1:-}" = "--fresh" ]; then
  docker volume rm -f "$NAME-home" >/dev/null
fi
docker run -d --name "$NAME" \
  -p "$JENKINS_PORT:8080" \
  -v "$NAME-home:/var/jenkins_home" \
  -e WIREMOCK_API_TOKEN \
  -e WIREMOCK_API_ENDPOINT \
  -e JENKINS_PORT \
  -e TRAIN_TRAVEL_BRANCH \
  "$NAME" >/dev/null

echo "Jenkins is starting at http://localhost:$JENKINS_PORT/ (admin / admin), building branch $TRAIN_TRAVEL_BRANCH"
echo "Logs: docker logs -f $NAME. Stop: jenkins/down.sh"
