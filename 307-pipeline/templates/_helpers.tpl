{{/*
===============================================
[307-pipeline 공통 Helper]
- 값 변환이 필요한 공통 로직만 정의
- 단순 설정은 각 템플릿에서 직접 관리
===============================================
*/}}


{{/*
노드 이름 → IP 조회

- 입력: dict "root" $ "name" <노드이름>
- 조회: global.nodes
- 노드가 없으면 Helm 렌더 단계에서 실패
- 301-hadoop과 동일한 global.nodes를 사용해 서버 IP와 일치시킴
*/}}
{{- define "pipeline.nodeIp" -}}
{{- $ip := "" -}}
{{- range .root.Values.global.nodes -}}
  {{- if eq .name $.name -}}
    {{- $ip = .ip -}}
  {{- end -}}
{{- end -}}
{{- required (printf "global.nodes에 노드 %q가 없습니다" .name) $ip -}}
{{- end -}}