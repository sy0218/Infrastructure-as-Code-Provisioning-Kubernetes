# Infrastructure as Code — Terraform × K8s (kubeadm lab)

kubeadm 3노드 클러스터(ap=192.168.56.200 control-plane, s1=.201, s2=.202) 위에
스택을 레이어로 쌓는다. **디렉토리 하나 = 독립 루트 모듈 = 독립 state**,
번호 접두사 = 적용 순서(100단위 간격 — 사이에 스택을 끼워 넣을 여백).

| 스택 | 내용 | 비고 |
|---|---|---|
| `100-base` | local-path(기본 StorageClass) + Longhorn(분산 스토리지) | 한 번 깔고 잊는 레이어 |
| `200-harbor` | Harbor 레지스트리 (NodePort 30002, HTTP) | tar 이미지 push 대상 |
| `300-monitoring` | alloy + prometheus + grafana (예정) | 이미지는 Harbor 에서 pull |

스토리지 두 종류의 역할 분담: **default 는 local-path**(지목 안 한 PVC 의 안전망),
복제가 필요한 데이터만 `storageClassName: longhorn` 으로 명시해서 쓴다.

## 적용 — 번호 순서대로, 스택마다 각자 init

```bash
cd 100-base      && terraform init && terraform plan && terraform apply
cd ../200-harbor && terraform init && terraform plan && terraform apply
```

- **Longhorn 선행 조건**: 각 노드에 open-iscsi/multipath/데이터 경로(`/data/longhorn`) 준비가
  먼저 돼 있어야 한다 — 노드 OS 레벨 작업이라 Terraform 밖(Ansible `longhorn_prereq` 롤)에서 처리.
- Harbor 접속: `terraform output harbor_url` (admin / 기본 비번은 variables.tf)
- 이미지 push 주소: `terraform output -raw harbor_registry`
- HTTP 레지스트리라 push/pull 클라이언트에 insecure 설정 필요
  (docker `insecure-registries`, containerd `certs.d hosts.toml`)

## 파기 — 역순

`200-harbor` destroy 후 `100-base` destroy. (PVC 가 StorageClass 보다 먼저 사라져야 정리가 깔끔)
Longhorn 은 uninstall 시 `deleting-confirmation-flag` 설정을 켜야 삭제가 진행된다.

## 규칙

- 버전은 전부 정확 고정 — 업그레이드는 버전 숫자를 고치는 커밋으로만
- `.terraform.lock.hcl` 은 커밋, `*.tfstate` 는 절대 커밋 금지 (.gitignore 참고)
