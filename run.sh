#!/usr/bin/env bash
set -euo pipefail

. vars.sh

region=$1

deploy_lambda $region
invoke_lambda $region
