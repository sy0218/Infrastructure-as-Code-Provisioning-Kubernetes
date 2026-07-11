# Infrastructure as Code — Terraform × K8s (kubeadm lab)

kubeadm 3노드 클러스터(ap=192.168.56.200 control-plane, s1=.201, s2=.202) 위에
스택을 레이어로 쌓는다. **디렉토리 하나 = 독립 루트 모듈 = 독립 state**,
번호 접두사 = 적용 순서.

| 스택 | 내용 | 비고 |
|---|---|---|
| `001-base` | local-path-provisioner (기본 StorageClass) | 한 번 깔고 잊는 레이어 |
| `002-harbor` | Harbor 레지스트리 (NodePort 30002, HTTP) | tar 이미지 push 대상 |
| `003-monitoring` | alloy + prometheus + grafana (예정) | 이미지는 Harbor 에서 pull |

## 적용 — 번호 순서대로, 스택마다 각자 init

```bash
cd 001-base    && terraform init && terraform plan && terraform apply
cd ../002-harbor && terraform init && terraform plan && terraform apply
```

- Harbor 접속: `terraform output harbor_url` (admin / 기본 비번은 variables.tf)
- 이미지 push 주소: `terraform output -raw harbor_registry`
- HTTP 레지스트리라 push/pull 클라이언트에 insecure 설정 필요
  (docker `insecure-registries`, containerd `certs.d hosts.toml`)

## 파기 — 역순

`002-harbor` destroy 후 `001-base` destroy. (PVC 가 StorageClass 보다 먼저 사라져야 정리가 깔끔)

## 규칙

- 버전은 전부 정확 고정 — 업그레이드는 버전 숫자를 고치는 커밋으로만
- `.terraform.lock.hcl` 은 커밋, `*.tfstate` 는 절대 커밋 금지 (.gitignore 참고)
