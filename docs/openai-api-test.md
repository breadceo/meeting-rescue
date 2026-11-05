# OpenAI API로 Meeting Intelligence 테스트

기존 `Custom Command` provider를 사용합니다. 앱 재빌드는 필요하지 않습니다.
기본 모델은 `gpt-6-luna`이고 Python 표준 라이브러리만 사용합니다.
반복 추출의 비용·응답 시간을 줄이기 위해 Luna의 reasoning effort는 `none`으로 지정합니다. 회의별 요약 품질은 실제 데이터로 검증해야 합니다.
이 스크립트는 회의 transcript와 앱이 포함하는 보조 맥락을 OpenAI에 전송합니다.
`store: false`를 설정하지만, 이것이 모든 API 데이터 보관을 없앤다는 의미는 아닙니다.

1. [API Keys](https://platform.openai.com/api-keys)에서 크레딧이 있는 **조직의 프로젝트**를 선택하고 키를 만드세요. `Restricted`에서 `Model capabilities → Responses (/v1/responses)`만 `Write`, 나머지는 `None`으로 지정하세요. `List models`는 호출하지 않습니다. 프로젝트에서 Luna 모델 접근도 허용되어 있어야 합니다. 키를 채팅·Custom command 입력란에 붙여 넣지 마세요.

2. 터미널에서 아래 명령을 실행하고 숨김 입력에 키를 붙여 넣으세요.

   ```sh
   python3 /Users/ethan/Documents/git/meeting-rescue/scripts/openai_meeting_intelligence.py --save-key
   ```

   `private/openai-api-key`에 권한 `600`으로 저장합니다. `private/`는 이미 Git에서 제외됩니다. 기존 키는 덮어쓰지 않습니다. `OPENAI_API_KEY`가 설정되어 있으면 파일보다 해당 환경변수를 우선 사용하므로, 크레딧 조직의 키인지 확인하세요.

3. 회의 데이터 없이 연결을 확인하세요. 이 명령은 짧은 API 요청 1회를 보내므로 API 사용량이 발생합니다.

   ```sh
   python3 /Users/ethan/Documents/git/meeting-rescue/scripts/openai_meeting_intelligence.py --smoke-test
   ```

   성공하면 `{"ok": true}`와 실제 API 입출력 토큰 수를 표시합니다. `401`은 키, `403`은 권한, `429`는 잔액 또는 rate limit을 확인하세요. `--smoke-test --dry-run`은 키·네트워크 없이 설정만 확인합니다.

4. 앱 설정에서 **자동 분석을 먼저 끄고**, `LLM provider`를 `Custom Command`로 선택한 다음 `Custom command`에 아래 한 줄을 넣으세요.

   ```sh
   /Users/ethan/.local/share/mise/installs/python/3.13.2/bin/python3 /Users/ethan/Documents/git/meeting-rescue/scripts/openai_meeting_intelligence.py
   ```

   이 경로는 현재 Mac에서 확인한 Python 실행 파일입니다. 다른 Mac에서는 `command -v python3` 결과로 바꾸세요. 스크립트 모델은 앱의 Model preset과 독립적이며, 변경하려면 명령 끝에 `--model gpt-5.4`처럼 지정하세요.

5. 전송해도 되는 짧은 과거 회의를 선택해 `분석`을 한 번 누르세요. Meeting Intelligence의 요약·근거·후보가 표시되는지 확인하고 [Usage](https://platform.openai.com/usage)에서 실제 사용량을 확인하세요. 실시간 갱신은 이후 Test Run으로 확인할 수 있습니다. 이전 설정으로 돌아가려면 provider를 `Codex`로 바꾸세요.

전체 요약과 실시간 patch는 저장소의 기존 JSON schema를 그대로 사용합니다.
HTTP 타임아웃은 45초이고 스크립트가 자동 재시도하지 않습니다. 앱의 자동 분석을 켜면 새 분석 요청이 반복되므로 테스트 후에 켜세요.
수정된 앱은 `MEETING_RESCUE_RESULT_FORMAT=json-v1`으로 어댑터에 요청하여 API 응답의
실제 모델명·입출력/합계/캐시/추론 토큰·response ID를 분석 기록에 저장합니다.
기존 앱과 직접 터미널 실행에서는 호환성을 위해 분석 JSON만 반환합니다.
사용량 화면과 분석 기록에서 토큰 `실측`/`추정`을 구분합니다. 비용은 참고 단가에 따른 추정이며 실제 청구는 Platform Usage에서 확인하세요.
기존 기록에는 실제 API 응답 메타데이터가 없으므로 과거 추정값은 그대로 보존합니다.

Test Run은 자동 분석 OFF 상태에서 로컬 미리보기만 갱신합니다. 외부 API를 한 번 호출하려면 재생 중 `분석`을 누르세요.
실제 키를 사용한 API 응답 검증은 오프라인 테스트에 포함되지 않습니다.

OpenAI 공식 문서: [Responses 구조화 출력](https://developers.openai.com/api/docs/guides/structured-outputs),
[GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna),
[API 크레딧 적용 범위](https://developers.openai.com/api/docs/guides/chatgpt-api-credits).
구독 혜택 크레딧은 연결된 조직의 Responses API 사용에 적용되며 Codex의 API 키 사용에는 적용되지 않습니다.

오프라인 테스트:

```sh
python3 -B -m unittest discover -s Tests -p 'openai_meeting_intelligence_tests.py'
```
