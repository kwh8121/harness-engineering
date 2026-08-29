# Context Budget — 에이전트별 컨텍스트 예산

토큰 절약의 절반은 여기서 나온다. 하네스 레벨을 낮게 유지해도 모든 에이전트에게 레포 전체를
읽히면 절약분이 사라진다.

`HarnessSpec` 의 `context:` 블록은 아래 기본값을 인스턴스화한 것이다.

## 불변 규칙

1. **`forbidden` 에는 항상 `full_repository_dump` 가 들어간다.** 예외 없다.
2. **산출물은 파일 경로로 넘긴다.** 프롬프트에 붙여넣은 내용은 세션이 끝날 때까지 컨텍스트에 남는다.
   보고서 본문을 붙여넣지 말고 `_workspace/harness/research/dependencies.md` 처럼 경로를 준다.
3. **세션 히스토리를 dispatch 프롬프트에 넣지 않는다.** 에이전트는 이 세션의 대화를 상속하지 않는다.
   필요한 것을 정확히 구성해서 준다.
4. **워커는 자기 서브에이전트를 스폰하지 않는다.** 프롬프트에 이 금지를 명시한다.
5. **dispatch 시 `model` 을 항상 명시한다.** 생략하면 세션의 가장 비싼 모델을 상속한다.

## 에이전트별 기본값

### implementer
```yaml
required:  [task, acceptance_criteria, assigned_unit_only, relevant_source, relevant_tests]
optional:  [dependency_report, baseline_report, architecture_doc, gate_log_path]
forbidden: [full_repository_dump, unrelated_docs, session_history, other_workers_context]
```
`assigned_unit_only` 가 핵심이다. H2/H3 에서 워커에게 다른 워커의 범위를 보여주면 손대기 시작한다.

### reviewer
```yaml
required:  [task, acceptance_criteria, git_diff, gate_results]
optional:  [architecture_doc, baseline_report]
forbidden: [full_repository_dump, unrelated_docs, session_history, implementer_reasoning]
```
`git_diff` + 게이트 결과면 충분하다. 레포를 다시 읽게 하지 않는다.
`implementer_reasoning` 을 넘기면 리뷰어가 구현자의 논리에 끌려간다 — 독립성이 리뷰의 전부다.

### dependency-mapper
```yaml
required:  [task, relevant_module_tree, imports, call_sites, api_contracts]
optional:  [db_schema, config_files]
forbidden: [full_repository_dump, test_fixtures, unrelated_docs]
```

### baseline-tester
```yaml
required:  [task, existing_tests, current_behavior, api_responses]
optional:  [test_fixtures, ci_history]
forbidden: [full_repository_dump, implementation_plan]
```
`implementation_plan` 을 주면 "앞으로 어떻게 될지"에 맞춰 기존 동작을 기술하기 시작한다.
baseline 은 **지금 무엇이 참인지**만 기록해야 한다.

### integrator
```yaml
required:  [task, worker_reports, git_diff, gate_results]
optional:  [dependency_report]
forbidden: [full_repository_dump, session_history, worker_prompts]
```

### orchestrator
```yaml
required:  [task, dag_state, agent_reports, gate_results, harness_spec]
optional:  [human_gate_history]
forbidden: [full_repository_dump, source_file_contents, session_history]
```
`source_file_contents` 가 `forbidden` 인 것이 중요하다. 소스를 읽기 시작한 orchestrator 는
곧 고치고 싶어진다. `tools` 에 Edit 이 없는 것과 같은 목적의 이중 방어다.

### deployment-agent
```yaml
required:  [release_artifact, migration_script, rollback_plan, health_check_endpoints]
optional:  [deploy_history]
forbidden: [full_repository_dump, secrets, source_file_contents]
```
`secrets` 는 값이 아니라 **이름과 위치만** 넘긴다.

## 게이트 결과를 넘기는 방법

게이트 로그 전문을 프롬프트에 넣지 않는다. `run-gates.sh` 는 이미
`_workspace/harness/gates/<tier>.log` 에 전문을 보존한다.

- 통과했을 때: `"fast/feature 게이트 통과 (로그: _workspace/harness/gates/)"` 한 줄
- 실패했을 때: 실패한 명령 이름 + **로그 파일 경로**. 에이전트가 필요한 만큼 직접 읽는다.

잘라낸 스택트레이스를 넘기는 것이 최악이다 — 잘린 지점 뒤에 원인이 있으면 엉뚱한 곳을 고친다.
