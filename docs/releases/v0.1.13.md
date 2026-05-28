# Meeting Rescue v0.1.13


- Live Watch 분석이 성공했는데도 현재 이슈가 `-`로 남을 수 있던 문제를 수정했습니다.
- 첫 live patch 분석에서 이전 현재 이슈가 비어 있으면 새 transcript chunk의 핵심 논점을 반드시 현재 이슈로 채우도록 보강했습니다.
- LLM provider가 여전히 `currentIssue`를 비워 반환해도 topic, 결정 후보, 액션 후보, note 근거로 현재 이슈를 보강하도록 했습니다.
