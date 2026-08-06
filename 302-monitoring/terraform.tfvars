# ===============================================
# [환경별 설정]
#   → 나머지는 variables.tf 기본값으로 동작한다.
#   ⚠ 이 파일은 커밋된다 → 시크릿 금지. Grafana 관리자 계정은 300-data-layer-base 의
#     Secret data-layer-secrets 에서 envFrom 으로 들어온다.
# ===============================================

# 200-harbor 의 output harbor_registry 와 같은 값
harbor_registry = "data-layer-harbor"

# build_and_push.sh 에 넘긴 값과 같은 값
image_tag = "v0.1.0"

# 로컬 Kafka 브로커의 JMX exporter(:9404) — Ansible host.yml kafka 그룹과 일치
kafka_jmx_targets = [
  { address = "192.168.56.200:9404", node = "ap", instance = "kafka-0" },
  { address = "192.168.56.201:9404", node = "s1", instance = "kafka-1" },
  { address = "192.168.56.202:9404", node = "s2", instance = "kafka-2" },
]
