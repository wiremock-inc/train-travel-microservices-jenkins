#!/usr/bin/env bash
# Stops the Jenkins started by jenkins/up.sh. Its Jenkins home volume is kept unless you pass --fresh to up.sh.
set -euo pipefail
docker rm -f train-travel-jenkins >/dev/null
echo "Stopped"
