# ADR 0001: Live Analysis Context Pipeline v2

상태: Accepted

날짜: 2026-05-26

## 맥락

Meeting Rescue의 live Meeting Intelligence는 사용자가 선택한 로컬 LLM CLI provider를 실행해 transcript를 분석한다. 현재 production 기본 흐름은 `codex exec` 기반의 stateless 호출이며, 앱은 raw transcript, analysis snapshot, candidate 상태, attempt log를 로컬에 저장한다.

실제 회의에서 transcript가 길어질수록 LLM prompt가 커지고, provider 실행 횟수와 timeout 위험이 증가했다. 특히 모든 참석자 metadata, 전체 또는 과도한 recent transcript context, 반복적인 full snapshot 출력은 token 사용량과 latency를 키운다. 동시에 live 중 history search DB를 건드리면 UI가 멈추거나 `검색 DB 확인중` 같은 내부 상태가 사용자 경험을 방해할 수 있다.

## 결정

### 1. Codex CLI는 production에서 stateless patch worker로 유지한다

`codex exec`는 계속 non-interactive one-shot worker로 사용한다. 앱이 meeting state, compact snapshot, transcript segment, candidate 상태, attempt log를 소유한다. Codex CLI session 자체를 장기 context store로 사용하지 않는다.

`codex app-server` 또는 persistent TTY bridge는 production path가 아니라 별도 experimental spike로 둔다.

### 2. previous snapshot 이후에는 patch-only를 기본 계약으로 한다

첫 분석은 full `AnalysisSnapshot`을 허용한다. 이후 live/manual/final continuation은 `AnalysisSnapshotPatch`를 기본 계약으로 사용한다.

escape hatch는 다음 경우에만 허용한다.

- 사용자가 수동으로 전체 재분석 또는 repair를 실행한다.
- schema mismatch 또는 품질 복구를 위해 명시적인 repair flow가 필요하다.
- 아주 짧은 회의에서 final refresh가 full snapshot으로 더 단순하고 안전하다.

### 3. live retrieval은 history FTS5와 분리한다

live analysis prompt 보강에는 active meeting 전용 ephemeral `LiveTranscriptIndex`를 사용한다. 기본 구현은 memory index로 두며, active meeting 변경 또는 회의 종료 시 reset한다.

기존 SQLite FTS5 history search DB는 과거 회의 검색과 회의 종료 후 안정 indexing에 사용한다. live analysis 중 history DB를 조회하거나 갱신하는 흐름은 이번 scope에 포함하지 않는다.

### 4. 기존 방식과 병립한다

고급 설정에 `Live context retrieval` 옵션을 둔다.

- `Off`: 기존 방식. `newTranscriptChunk + recentTranscriptContext`만 사용한다.
- `Memory live index`: active meeting 전용 memory index에서 관련 과거 chunk top 0~3개를 추가한다.

`History FTS5 live retrieval`은 이번 구현에 넣지 않고 후속 backlog로만 남긴다.

### 5. UX는 live index 내부 구현을 숨긴다

사용자는 live 중 검색 index 상태를 볼 필요가 없다. live 화면에서는 다음 정보만 조용히 보여준다.

- automatic analysis on/off
- 다음 analysis trigger 조건
- 최근 analysis 시각 또는 freshness

context/retrieval 상세는 Analysis 실행 상세에서만 확인한다.

## 기대 효과

- provider 호출당 prompt 크기를 줄인다.
- live analysis의 timeout 위험을 낮춘다.
- history search indexing과 live analysis path를 분리해 UI 멈춤 위험을 낮춘다.
- retrieval off/on 비교가 가능해진다.
- Q&A 구현 전에도 live analysis가 필요한 과거 맥락 일부를 제한적으로 참조할 수 있다.

## 리스크와 대응

- 첫 full snapshot 품질이 낮으면 patch가 그 위에 누적될 수 있다.
  - 대응: 수동 전체 재분석/repair escape hatch를 둔다.
- patch schema가 삭제/정정을 충분히 표현하지 못할 수 있다.
  - 대응: 필요 시 delete/supersede 필드를 patch schema에 추가한다.
- live memory retrieval이 부정확한 chunk를 넣으면 분석 품질이 낮아질 수 있다.
  - 대응: score threshold를 두고, threshold 미만이면 retrieved chunk를 0개로 둔다.
- 옵션 증가로 설정 화면이 복잡해질 수 있다.
  - 대응: retrieval mode는 고급 설정에 둔다.

## 이번 scope에서 제외

- `History FTS5 live retrieval`
- multi-meeting Q&A
- NotebookLM-style Q&A thread
- persistent TTY bridge production 적용
- `codex app-server` provider production 적용

## 후속 검토

- `History FTS5 live retrieval`은 과거 회의 맥락 자동 보강, 프로젝트별 장기 맥락, NotebookLM-style Q&A에서 별도 backlog로 검토한다.
- persistent provider는 official/stable protocol 또는 충분한 spike 검증 이후 다시 판단한다.
