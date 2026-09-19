{{/*
===============================================
[308-spark 공통 Helper]
- 노드 이름 → IP 조회만 정의한다 (HDFS 클라이언트 설정 · nodeNames 실존 검사)
- 단순 조합은 각 템플릿에서 직접 처리한다
===============================================
*/}}


{{/*
global.nodes 에서 노드 이름으로 IP 를 조회한다. 없는 이름은 렌더를 실패시킨다.

인자: dict "root" $ "name" <노드이름>
*/}}
{{- define "spark.nodeIp" -}}
{{- $ip := "" -}}
{{- range .root.Values.global.nodes -}}
{{- if eq .name $.name -}}{{- $ip = .ip -}}{{- end -}}
{{- end -}}
{{- required (printf "global.nodes 에 노드 %q 가 없다" .name) $ip -}}
{{- end -}}
