# proxy-reload-test

> 같은 백엔드 앞에 **Nginx**와 **Envoy**를 나란히 세워두고,
> 업스트림이 바뀔 때 두 프록시가 어떻게 다르게 반응하는지 직접 확인하는 실습입니다.

관찰할 것은 딱 하나입니다.
**에러가 언제 멈추는가, 그리고 그 대가로 무엇을 했는가.**

---

## 구성

```
                     ┌── :8080  nginx  ──┐
  watch.sh ─────────┤                    ├──→ backend-a  172.28.0.11
   (curl loop)       └── :8081  envoy  ──┘     backend-b  172.28.0.12
                                                backend-c  172.28.0.13 (처음엔 꺼져 있음)
                          :9901  envoy admin
```

| | 업스트림 목록이 어디 있나 | 바꾸려면 |
|---|---|---|
| Nginx | `nginx/default.conf` 안 | 파일 수정 + `nginx -s reload` |
| Envoy | `envoy/eds.yaml` (구독) | 파일만 교체, **재시작 없음** |

> 컨테이너 IP를 고정한 이유: EDS 엔드포인트는 DNS 이름이 아니라 **IP**로 표현됩니다.
> 실습을 결정론적으로 만들기 위해 서브넷을 고정했습니다.
> 실제 환경에서는 이 IP가 계속 바뀌고, 그래서 컨트롤 플레인이 필요해집니다.

---

## 시작하기

### EC2에서 (권장)

발표자가 공지한 CloudFormation 템플릿으로 스택을 만드세요.
`cloudformation/lab-instance.yaml`

- SSH 키페어 **불필요** — 콘솔에서 `Connect → Session Manager`
- 보안그룹 인바운드 규칙 **불필요**
- Docker 설치, repo clone, 이미지 pull, 컨테이너 기동까지 자동

접속 후:

```bash
ls ~/READY                 # 파일이 보이면 준비 완료
cd ~/proxy-reload-test
```

### 로컬에서

Docker와 Docker Compose만 있으면 됩니다.

```bash
git clone <this-repo> && cd proxy-reload-test
chmod +x scripts/*.sh
docker compose --profile extra pull
docker compose up -d
```

---

## 실습

### Step 1 — 관찰 창 띄우기

터미널을 **두 개** 엽니다. 첫 번째 창:

```bash
./scripts/watch.sh
```

```
  time      nginx :8080        envoy :8081
  --------------------------------------------
  14:02:11  200 backend-a     200 backend-a
  14:02:12  200 backend-b     200 backend-b
  14:02:12  200 backend-a     200 backend-a
```

양쪽 모두 `backend-a`와 `backend-b`를 번갈아 부르고 있습니다.
**이 창은 실습이 끝날 때까지 끄지 않습니다.**

### Step 2 — 백엔드를 교체한다

두 번째 창에서:

```bash
docker compose stop backend-b
docker compose up -d backend-c
```

`backend-b`가 사라지고, 새 IP를 가진 `backend-c`가 떴습니다.
ASG가 인스턴스를 교체했거나, ECS가 태스크를 새로 띄운 상황입니다.

관찰 창을 보세요.

```
  14:03:40  200 backend-a     200 backend-a
  14:03:41  502 -             503 -
  14:03:41  200 backend-a     200 backend-a
  14:03:42  502 -             503 -
```

> **둘 다 실패합니다.** Envoy도 마법이 아닙니다.
> 아무도 두 프록시에게 "backend-b는 죽었고 backend-c가 새로 왔다"고 말해주지 않았습니다.
>
> 그리고 방금 띄운 `backend-c`는 **아무 트래픽도 받지 못하고 있습니다.**
> 스케일 아웃을 했는데 새 용량이 그대로 노는 상황입니다.

차이는 여기서부터 시작합니다.

### Step 3a — Envoy를 고친다

```bash
./scripts/eds-set.sh 172.28.0.11 172.28.0.13
```

관찰 창:

```
  14:04:15  502 -             503 -
  14:04:16  200 backend-a     200 backend-a
  14:04:16  502 -             200 backend-c      ← 복구
  14:04:17  200 backend-a     200 backend-a
```

한 일: **파일 하나 교체.**
하지 않은 일: 프로세스 재시작, reload 명령, 커넥션 끊김.

바뀐 파일이 무엇인지 확인해 보세요.

```bash
cat envoy/eds.yaml     # 엔드포인트 목록만 바뀌었다
cat envoy/cds.yaml     # 클러스터 정의는 그대로다
```

> **"무엇을 부를 것인가"는 그대로이고, "누가 거기 있는가"만 바뀌었습니다.**
> 이 둘이 분리되어 있다는 것 — 그게 CDS와 EDS를 나눈 이유입니다.

### Step 3b — Nginx를 고친다

`nginx/default.conf`를 열어 업스트림을 수정합니다.

```diff
  upstream backend {
      server 172.28.0.11:5678 max_fails=0;   # backend-a
-     server 172.28.0.12:5678 max_fails=0;   # backend-b
+     server 172.28.0.13:5678 max_fails=0;   # backend-c
  }
```

저장하고 — 관찰 창을 보세요. **아직 502가 계속됩니다.**
파일을 고쳤다고 반영되지 않습니다.

```bash
docker compose exec nginx nginx -t          # 문법 검증
docker compose exec nginx nginx -s reload   # 이제 반영
```

이제 양쪽 다 복구되었습니다.

### Step 4 — 정말 재시작이 없었는지 확인한다

```bash
./scripts/proof.sh
```

- **nginx worker PID**: Step 3b의 reload로 통째로 바뀌었습니다.
  기존 worker는 종료되었고, 그들이 들고 있던 커넥션 풀과 캐시도 함께 사라졌습니다.
- **envoy `server.uptime`**: EDS를 몇 번 갱신하든 계속 증가하기만 합니다.
  `hot_restart_epoch`도 0 그대로입니다.

Envoy에게 지금 상태를 직접 물어볼 수도 있습니다.

```bash
curl -s localhost:9901/clusters | grep backend
curl -s localhost:9901/config_dump | head -40
curl -s localhost:9901/stats | grep cluster.backend.update_success
```

> Nginx에게 "지금 설정이 뭐야?"라고 물으면 **파일을 열어봐야** 합니다.
> Envoy에게 물으면 **프로세스가 직접 대답합니다.**

### 처음으로 되돌리기

```bash
./scripts/reset.sh
```

---

## 실습이 말하는 것

| | Nginx | Envoy |
|---|---|---|
| 장애를 겪었나 | ○ | ○ |
| 복구했나 | ○ | ○ |
| **복구의 대가** | 파일 수정 + reload + worker 교체 | 파일 교체만 |
| 설정의 진실 | conf 파일 | 컨트롤 플레인 (여기서는 파일) |
| 현재 상태 조회 | 파일 읽기 | `/config_dump` |

차이는 **복구할 수 있느냐**가 아니라 **복구에 무엇이 드느냐**입니다.
그리고 이 비용은 변경 주기가 짧아질수록 커집니다.

- 월 1회 변경 → reload 모델로 충분합니다
- 분 단위 변경 → 자동화가 필요합니다 (Consul-template, Lambda + SSM)
- 초 단위 변경 → 설정을 파일이 아니라 **API로 다뤄야 합니다**

이 실습에서는 파일이 컨트롤 플레인 역할을 했습니다.
실제 환경에서는 그 자리에 gRPC 컨트롤 플레인이 들어갑니다.
**Envoy 입장에서는 둘 다 똑같은 xDS입니다.**

---

## 기술 메모

### 왜 `eds-set.sh`로 파일을 쓰나

Envoy의 파일 기반 xDS는 inotify의 **move** 이벤트로 갱신을 감지합니다.
그래서 스크립트는 임시 파일에 쓴 뒤 같은 디렉터리 안에서 `mv` 합니다 (atomic rename).

실제 운영에서 심볼릭 링크를 원자적으로 바꿔치기하는 것과 같은 이유입니다.
**반쯤 쓰인 설정 파일을 프록시가 읽는 일이 없어야** 하니까요.
설정 교체는 그 자체로 원자적이어야 합니다.

에디터로 직접 수정해도 대부분 동작합니다(대부분의 에디터가 atomic save를 씁니다).
반영이 안 되면 스크립트를 쓰세요.

### 왜 `max_fails=0`인가

Nginx 기본값(`max_fails=1, fail_timeout=10s`)은 죽은 서버를 10초간 목록에서 빼줍니다.
그러면 502가 10초에 한 번만 보여서 관찰이 어렵습니다.

다만 이건 실습 편의 이상의 의미가 있습니다.
**passive health check는 죽은 서버를 가려줄 뿐, 새로 뜬 서버를 발견해주지는 못합니다.**
Step 2에서 `backend-c`가 트래픽을 못 받은 이유가 그것입니다.

### 왜 `proxy_next_upstream off`인가

기본값이면 Nginx가 실패를 다른 서버로 넘겨 502를 감춥니다.
장애가 눈에 안 보이면 실습이 성립하지 않아서 껐습니다.

### 왜 디렉터리를 마운트하나

파일 단위로 bind mount 하면 atomic rename이 마운트를 끊어버립니다.
`./envoy`와 `./nginx`를 디렉터리째 마운트하는 이유입니다.

---

## 정리

실습이 끝나면 **CloudFormation 스택을 삭제**해 주세요.

```bash
docker compose --profile extra down    # 로컬에서 실습한 경우
```
