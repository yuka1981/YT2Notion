#!/bin/bash

URL="$1"
LANG="${2:-zh}"
SUMMARY_LANG="${3:-zh-TW}"
CLI_TOOL="${4:-claude}"
API="http://10.106.37.191:9001/transcribe"

if [ -z "$URL" ]; then
  echo "Usage: transcribe_youtubh.sh \"YOUTUBE_URL\" [transcription_lang] [summary_lang] [cli_tool]"
  echo ""
  echo "  transcription_lang  Language for transcription (default: zh)"
  echo "  summary_lang        Language for summary (default: zh-TW, or: en)"
  echo "  cli_tool            CLI to summarize (default: claude, or: codex, gemini)"
  exit 1
fi

TIMESTAMP=$(date +%s)
TRANSCRIPT_FILE="./transcript_${TIMESTAMP}.txt"
SUMMARY_FILE="./summary_${TIMESTAMP}.txt"

RESPONSE=$(curl -s -m 1800 -X POST "$API" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"$URL\", \"lang\": \"$LANG\"}")

TEXT=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['text'])" 2>/dev/null)

if [ -n "$TEXT" ]; then
  echo "$TEXT" > "$TRANSCRIPT_FILE"
  echo "$TRANSCRIPT_FILE"

  # Build summarization prompt
  case "$SUMMARY_LANG" in
    zh-TW) PROMPT="用繁體中文摘要以下影片逐字稿" ;;
    en)    PROMPT="Summarize the following video transcript in English" ;;
    *)     PROMPT="Summarize the following video transcript in ${SUMMARY_LANG}" ;;
  esac

  # Run summarization
  case "$CLI_TOOL" in
    claude) SUMMARY=$(echo "$TEXT" | claude -p "$PROMPT" 2>/dev/null) ;;
    codex)  SUMMARY=$(echo "$TEXT" | codex exec "$PROMPT" 2>/dev/null) ;;
    gemini) SUMMARY=$(echo "$TEXT" | gemini -p "$PROMPT" 2>/dev/null) ;;
    *)
      echo "ERROR: Unknown CLI tool '$CLI_TOOL'. Use: claude, codex, gemini" >&2
      SUMMARY=""
      ;;
  esac

  if [ -n "$SUMMARY" ]; then
    echo "$SUMMARY" > "$SUMMARY_FILE"
    echo "$SUMMARY_FILE"
  else
    echo "WARNING: Summarization failed or produced empty output. Transcript saved." >&2
  fi
else
  ERROR=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('detail','unknown error'))" 2>/dev/null || echo "$RESPONSE")
  echo "ERROR: $ERROR" >&2
  exit 1
fi
