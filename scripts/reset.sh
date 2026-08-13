#!/usr/bin/env bash
# 실습을 처음 상태로 되돌린다.
set -euo pipefail
cd "$(dirname "$0")/.."

git checkout -- envoy/eds.yaml nginx/default.conf 2>/dev/null || true
docker compose --profile extra down
docker compose up -d
echo "초기 상태로 복구되었습니다."
