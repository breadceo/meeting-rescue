#!/usr/bin/env python3
"""OpenAI Responses API adapter for Meeting Rescue's Custom Command provider."""

import argparse
import getpass
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
KEY_PATH = ROOT / "private" / "openai-api-key"
RESOURCES = ROOT / "Sources" / "MeetingRescue" / "Resources"


def save_key(path, key):
    key = key.strip()
    if not key or any(c.isspace() for c in key):
        raise ValueError("API 키가 비어 있거나 공백이 포함되어 있습니다.")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Exclusive creation avoids replacing an existing credential or following a symlink.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        output.write(key + "\n")


def load_key(path):
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        if not path.exists():
            raise ValueError("API 키가 없습니다. 먼저 --save-key를 실행하세요.")
        if path.stat().st_mode & 0o077:
            raise ValueError("키 파일 권한이 너무 넓습니다. chmod 600으로 변경하세요.")
        key = path.read_text(encoding="utf-8").strip()
    if not key or any(c.isspace() for c in key):
        raise ValueError("유효한 API 키를 저장하거나 OPENAI_API_KEY를 설정하세요.")
    return key


def api_schema(value):
    if isinstance(value, list):
        return [api_schema(item) for item in value]
    if not isinstance(value, dict):
        return value
    result = {key: api_schema(item) for key, item in value.items() if key != "$schema"}
    if "enum" in result and "type" not in result:
        result["type"] = "string"
    return result


def build_request(prompt, model, smoke_test=False):
    if not prompt.strip():
        raise ValueError("분석할 prompt가 없습니다. 앱 Custom Command에서 실행하세요.")
    if smoke_test:
        schema = {"type": "object", "additionalProperties": False,
                  "properties": {"ok": {"type": "boolean"}}, "required": ["ok"]}
        name = "connection_test"
    else:
        # Only inspect app instructions, never transcript content after Payload.
        instructions, separator, _ = prompt.partition("\nPayload:\n")
        if not separator:
            raise ValueError("Meeting Rescue prompt의 Payload 구분자가 없습니다.")
        is_patch = "JSON patch 객체" in instructions
        name = "meeting_patch" if is_patch else "meeting_snapshot"
        filename = "analysis-patch-output.schema.json" if is_patch else "analysis-output.schema.json"
        schema = api_schema(json.loads((RESOURCES / filename).read_text(encoding="utf-8")))
    body = {
        "model": model,
        "input": prompt,
        "store": False,
        "max_output_tokens": 8000 if not smoke_test else 128,
        "text": {"format": {"type": "json_schema", "name": name, "strict": True, "schema": schema}},
    }
    if model == "gpt-6-luna":
        # Luna defaults to medium reasoning; use none for this frequent extraction task.
        body["reasoning"] = {"effort": "none"}
    return body


def call_api(body, key):
    request = Request("https://api.openai.com/v1/responses",
                      data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                      headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
                      method="POST")
    try:
        # One request only: retries can incur additional charges after timeouts.
        with urlopen(request, timeout=45) as response:
            return json.load(response)
    except HTTPError as error:
        hints = {
            400: "모델과 JSON schema 요청을 확인하세요.",
            401: "API 키를 확인하세요.",
            403: "키의 프로젝트·모델 권한을 확인하세요.",
            429: "해당 조직의 크레딧 잔액과 rate limit을 확인하세요.",
        }
        # Do not include server bodies; they can echo sensitive request content.
        raise ValueError("OpenAI HTTP {}: {}".format(
            error.code, hints.get(error.code, "OpenAI API 상태를 확인하세요."))) from None
    except (URLError, TimeoutError):
        raise ValueError("OpenAI API 연결 실패 또는 45초 초과. 네트워크를 확인하세요.") from None


def response_text(response):
    if response.get("status") != "completed":
        raise ValueError("OpenAI 응답이 완료되지 않았습니다. 출력 한도 또는 API 상태를 확인하세요.")
    parts = []
    for item in response.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if content.get("type") == "refusal":
                raise ValueError("OpenAI가 분석 요청을 거절했습니다.")
            if content.get("type") == "output_text":
                parts.append(content["text"])
    text = "".join(parts)
    try:
        parsed = json.loads(text)
    except (ValueError, TypeError):
        raise ValueError("OpenAI 응답에 유효한 JSON 객체가 없습니다.") from None
    if not isinstance(parsed, dict):
        raise ValueError("OpenAI 응답은 JSON 객체여야 합니다.")
    return json.dumps(parsed, ensure_ascii=False)


def app_result(response, output):
    usage = response.get("usage") or {}
    model = response.get("model")
    counts = [usage.get(name) for name in ("input_tokens", "output_tokens", "total_tokens")]
    if not isinstance(model, str) or not model.strip() or any(type(n) is not int or n < 0 for n in counts):
        raise ValueError("OpenAI 응답에 실제 모델명 또는 토큰 사용량이 없습니다.")
    return {
        "meetingRescueResultVersion": 1,
        "output": output,
        "usage": {
            "modelName": model,
            "inputTokens": counts[0], "outputTokens": counts[1], "totalTokens": counts[2],
            "cachedInputTokens": (usage.get("input_tokens_details") or {}).get("cached_tokens", 0),
            "cacheWriteInputTokens": (usage.get("input_tokens_details") or {}).get("cache_write_tokens"),
            "reasoningOutputTokens": (usage.get("output_tokens_details") or {}).get("reasoning_tokens", 0),
            "responseID": response.get("id"),
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--save-key", action="store_true", help="API 키를 숨김 입력으로 로컬 저장")
    parser.add_argument("--key-file", type=Path, default=KEY_PATH)
    parser.add_argument("--model", default="gpt-6-luna")
    parser.add_argument("--smoke-test", action="store_true", help="회의 데이터 없이 연결 테스트 (소액 API 사용)")
    parser.add_argument("--dry-run", action="store_true", help="네트워크·키 없이 요청 설정만 확인")
    args = parser.parse_args()
    try:
        if args.save_key:
            if not sys.stdin.isatty():
                raise ValueError("--save-key는 사용자 터미널에서 실행하세요.")
            save_key(args.key_file, getpass.getpass("OpenAI API key (화면에 표시되지 않음): "))
            print("저장 완료: {} (권한 600)".format(args.key_file))
            return 0
        prompt = 'Return a JSON object with ok set to true.' if args.smoke_test else sys.stdin.read()
        body = build_request(prompt, args.model, args.smoke_test)
        if args.dry_run:
            print(json.dumps({"model": body["model"], "store": body["store"],
                              "format": body["text"]["format"]["name"],
                              "prompt_characters": len(prompt), "network_request": False}))
            return 0
        response = call_api(body, load_key(args.key_file))
        output = response_text(response)
        if args.smoke_test and json.loads(output).get("ok") is not True:
            raise ValueError("연결 테스트 응답의 ok가 true가 아닙니다.")
        if not args.smoke_test and os.environ.get("MEETING_RESCUE_RESULT_FORMAT") == "json-v1":
            print(json.dumps(app_result(response, output), ensure_ascii=False))
        else:
            print(output)
        usage = response.get("usage", {})
        print("OpenAI usage: input_tokens={} output_tokens={}".format(
            usage.get("input_tokens", "?"), usage.get("output_tokens", "?")), file=sys.stderr)
        return 0
    except FileExistsError:
        print("오류: 키 파일이 이미 있습니다. 기존 키를 덮어쓰지 않았습니다.", file=sys.stderr)
    except (ValueError, OSError) as error:
        # JSON/API errors above have safe messages; filesystem errors can include local paths.
        print("오류: {}".format(error) if isinstance(error, ValueError)
              else "오류: 로컬 파일을 읽거나 저장하지 못했습니다.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
