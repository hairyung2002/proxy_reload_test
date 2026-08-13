#!/usr/bin/env bash
# 두 프록시를 동시에 두드리며 상태 코드와 응답 백엔드를 출력한다.
# 실습 내내 이 창을 띄워둘 것. 관찰 대상은 "에러가 언제 멈추는가" 하나뿐이다.

NGINX_URL="http://localhost:8080/"
ENVOY_URL="http://localhost:8081/"

hit() {
  local url=$1 body code
  body=$(curl -s -m 2 -o /tmp/_body.$$ -w '%{http_code}' "$url" 2>/dev/null) || body="000"
  code="$body"
  body=$(tr -d '\r\n' < /tmp/_body.$$ 2>/dev/null | head -c 12)
  rm -f /tmp/_body.$$
  if [ "$code" = "200" ]; then
    printf "\033[32m%3s %-10s\033[0m" "$code" "$body"
  else
    printf "\033[31m%3s %-10s\033[0m" "$code" "-"
  fi
}

echo "  time      nginx :8080        envoy :8081"
echo "  --------------------------------------------"
while true; do
  printf "  %s  " "$(date +%H:%M:%S)"
  hit "$NGINX_URL"
  printf "   "
  hit "$ENVOY_URL"
  printf "\n"
  sleep 0.5
done
