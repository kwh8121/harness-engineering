---
name: reviewing-skill-md
description: Use when reviewing a SKILL.md file before shipping it, extending an existing skill, or auditing a project's skills for structure, discoverability, size, or anti-patterns.
---

# Reviewing SKILL.md

## Overview
임의의 SKILL.md 파일 하나를 구조·발견성(discoverability)·크기·안티패턴 관점에서 진단하고 pass/warn/fail 리포트를 만든다. 코드를 수정하지 않는 리뷰 전용 스킬이다.

## When to Use
- 새 SKILL.md를 작성해 배포하기 전
- 기존 스킬을 확장한 뒤 품질을 재점검할 때
- 프로젝트의 여러 스킬 중 하나를 감사(audit)할 때

## 실행 흐름
1. 리뷰 대상 SKILL.md 경로를 확인한다.
2. `scripts/collect-metrics.sh <경로>`를 실행해 정량 지표(줄 수, frontmatter 길이, 키워드 카운트 등)를 수집한다.
3. `references/checklist.md`를 읽고 A(Frontmatter & Discovery)/B(구조 & 콘텐츠)/C(크기 & 분리 신호)/D(안티패턴) 4개 카테고리를 판정한다. 정량 지표는 스크립트 결과를 쓰고, 정성 항목은 대상 파일을 직접 읽어 판단한다.
4. 카테고리별 pass/warn/fail과 근거·권고를 정리해 마크다운 리포트로 출력한다.
5. `references/checklist.md`의 종합 판정 규칙에 따라 전체 등급(high/med/low/pass)을 매기고 우선순위 개선 Top 3를 제시한다.

리뷰 기준의 전체 상세는 `references/checklist.md`를 참조한다.
