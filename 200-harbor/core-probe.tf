# ===============================================
# [harbor-core probe 완화]
#
# 큰 이미지 push 시 core 응답 지연으로
# liveness 실패 → core 재시작 → push 실패가 발생함.
#
# liveness/readiness probe의 timeout과 실패 허용 횟수를 늘려
# 일시적인 부하로 core가 재시작되지 않도록 완화함.
#
# Harbor 1.18.4는 liveness 설정을 values로 노출하지 않아
# 배포 후 kubectl patch로 적용함.
# ===============================================

resource "terraform_data" "core_probe_relax" {
  # 릴리스가 갱신/재설치되면(revision 증가) 패치를 다시 건다
  triggers_replace = [helm_release.harbor.metadata.revision]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl --kubeconfig ${pathexpand(var.kubeconfig_path)} -n harbor patch deployment harbor-core --type=json -p='[
        {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":5},
        {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/failureThreshold","value":6},
        {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":5}
      ]'
    EOT
  }
}
