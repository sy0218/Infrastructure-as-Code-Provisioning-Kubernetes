{{/*
===============================================
[301-elasticsearch 공통 Helper]
- 값 변환이 끼는 조합(표 → 목록)만 정의 — 단순 연결은 각 템플릿에서 직접
===============================================
*/}}


{{/*
노드 이름 → IP 조회 (global.nodes) — 표에 없는 이름은 렌더 단계에서 실패
- 입력: dict "root" $ "name" <노드이름>
*/}}
{{- define "elasticsearch.nodeIp" -}}
{{- $ip := "" -}}
{{- range .root.Values.global.nodes -}}
  {{- if eq .name $.name -}}
    {{- $ip = .ip -}}
  {{- end -}}
{{- end -}}
{{- required (printf "global.nodes 에 노드 %q 가 없다" .name) $ip -}}
{{- end -}}


{{/*
discovery.seed_hosts → nodeNames 전부의 노드IP:transport 목록
예: 192.168.56.38:9300,192.168.56.39:9300,192.168.56.40:9300
*/}}
{{- define "elasticsearch.seedHosts" -}}
{{- $l := list -}}
{{- range .Values.nodeNames -}}
{{- $l = append $l (printf "%s:%d" (include "elasticsearch.nodeIp" (dict "root" $ "name" .)) (int $.Values.ports.transport)) -}}
{{- end -}}
{{- join "," $l -}}
{{- end -}}


{{/*
cluster.initial_master_nodes → 파드 이름(node.name) 목록
예: elasticsearch-0,elasticsearch-1,elasticsearch-2
*/}}
{{- define "elasticsearch.initialMasters" -}}
{{- $l := list -}}
{{- range $i, $_ := .Values.nodeNames -}}
{{- $l = append $l (printf "elasticsearch-%d" $i) -}}
{{- end -}}
{{- join "," $l -}}
{{- end -}}
