# ===============================================
# [Terraform Output]
#   → 조회: terraform -chdir=102-ingress output -raw <이름>
# ===============================================

# 앱 스택의 접속 주소가 전부 이 IP 로 모인다. /etc/hosts(Ansible ingress_vip)와
# 305-api 의 hostAliases 가 같은 값을 써야 이름이 여기로 풀린다.
output "ingress_vip" {
  description = "HTTP 서비스 공통 진입점 VIP — 이름은 /etc/hosts 가 이 주소로 푼다"
  value       = var.ingress_vip
}

# 각 앱 스택 Ingress 의 ingressClassName 이 이 값이어야 이 컨트롤러가 집어 간다.
# 차트가 이 클래스를 기본값으로 만들지 않으므로 매니페스트에 반드시 명시해야 한다.
output "ingress_class_name" {
  description = "앱 스택 Ingress 가 spec.ingressClassName 에 적어야 하는 값"
  value       = "nginx"
}
