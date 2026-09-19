{{/*
===============================================
[304-airflow-rsync 공통 Helper]

노드 이름 → IP 변환처럼 값 조회가 필요한 조합만 정의한다.
단순 조합은 각 템플릿에서 직접 처리한다.
===============================================
*/}}


{{/*
global.nodes에서 노드 이름으로 IP를 조회한다.
존재하지 않는 노드는 Helm 렌더링을 실패시킨다.

인자:
- name  : 노드 이름
- nodes : global.nodes
*/}}
{{- define "airflowRsync.nodeIp" -}}
{{- $name := .name -}}
{{- $ip := "" -}}
{{- range .nodes -}}
{{- if eq .name $name -}}{{- $ip = .ip -}}{{- end -}}
{{- end -}}
{{- required (printf "노드 %q 가 global.nodes 에 없다" $name) $ip -}}
{{- end -}}


{{/*
rsync 대상 노드 이름을 IP 목록으로 변환한다.
결과는 스크립트에서 사용할 공백 구분 문자열이다.
*/}}
{{- define "airflowRsync.targetIps" -}}
{{- $ips := list -}}
{{- range .Values.targets.nodeNames -}}
{{- $ips = append $ips (include "airflowRsync.nodeIp" (dict "name" . "nodes" $.Values.global.nodes)) -}}
{{- end -}}
{{- join " " $ips -}}
{{- end -}}