#!/usr/bin/env bash
set -euo pipefail
TOTALVM_REPOSITORY_PROFILE=server bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/package-repository.sh"
