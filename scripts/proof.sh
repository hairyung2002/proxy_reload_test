#!/usr/bin/env bash
# "정말 재시작이 없었는가"를 증명한다.

echo "=== nginx worker PID ==================================="
echo "  (reload 하면 이 PID들이 통째로 바뀐다)"
docker compose exec -T nginx sh -c "ps -eo pid,args | grep '[n]ginx: worker'"

echo
echo "=== envoy uptime ======================================="
echo "  (EDS를 몇 번을 갱신해도 이 값은 계속 증가하기만 한다)"
curl -s localhost:9901/stats | grep -E "server.uptime|server.live|server.hot_restart_epoch"

echo
echo "=== envoy 가 지금 알고 있는 엔드포인트 ================="
curl -s "localhost:9901/clusters?format=json" \
  | grep -oE '"address": ?"[0-9.]+"|"port_value": ?[0-9]+' \
  || curl -s localhost:9901/clusters | grep "backend::"

echo
echo "=== EDS 갱신 횟수 ======================================"
curl -s localhost:9901/stats | grep -E "cluster.backend.update_success|cluster.backend.membership"
