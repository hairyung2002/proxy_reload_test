#!/usr/bin/env bash
# EDS 엔드포인트 목록을 다시 쓴다.
#
#   ./scripts/eds-set.sh 172.28.0.11 172.28.0.13
#
# 왜 스크립트로 쓰는가:
#   Envoy의 파일 기반 xDS는 inotify의 "move" 이벤트로 갱신을 감지한다.
#   그래서 임시 파일에 쓴 뒤 같은 디렉터리 안에서 mv 한다 (atomic rename).
#   실제 운영에서 심볼릭 링크를 원자적으로 바꿔치기하는 것과 같은 이유다.
#   → 설정 교체는 그 자체로 원자적이어야 한다.

set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -eq 0 ]; then
  echo "usage: $0 <ip> [ip ...]" >&2
  echo "example: $0 172.28.0.11 172.28.0.13" >&2
  exit 1
fi

TMP="envoy/.eds.yaml.tmp"
{
  echo "# EDS — 엔드포인트 목록"
  echo "version_info: \"$(date +%s)\""
  echo "resources:"
  echo "  - \"@type\": type.googleapis.com/envoy.config.endpoint.v3.ClusterLoadAssignment"
  echo "    cluster_name: backend"
  echo "    endpoints:"
  echo "      - lb_endpoints:"
  for ip in "$@"; do
    echo "          - endpoint:"
    echo "              address:"
    echo "                socket_address:"
    echo "                  address: ${ip}"
    echo "                  port_value: 5678"
  done
} > "$TMP"

mv "$TMP" envoy/eds.yaml
echo "eds.yaml 갱신됨 → $*"
echo "Envoy 재시작 없음. reload 명령 없음. 잠시 후 watch 창을 확인하세요."
