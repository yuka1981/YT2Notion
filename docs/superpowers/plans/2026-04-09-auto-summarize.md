# Auto-Summarize Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modify `transcribe_youtubh.sh` to automatically summarize transcripts using an LLM CLI tool (claude/codex/gemini) after transcription.

**Architecture:** After the existing transcription logic, add a summarization step that pipes the transcript text into a chosen CLI tool with a language-specific prompt. The timestamp is extracted so both files pair up. Summarization failure does not affect the transcript.

**Tech Stack:** Bash, claude CLI (`-p`), codex CLI (`exec`), gemini CLI (`-p`)

---

### File Structure

- Modify: `transcribe_youtubh.sh` (the only file)

---

### Task 1: Update argument parsing and usage message

**Files:**
- Modify: `transcribe_youtubh.sh:1-11`

- [ ] **Step 1: Update the argument defaults and usage message**

Replace lines 1-11 of `transcribe_youtubh.sh` with:

```bash
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
```

- [ ] **Step 2: Verify the script still prints usage when called with no args**

Run: `bash transcribe_youtubh.sh`
Expected: Usage message with the new arguments shown, exit code 1.

- [ ] **Step 3: Commit**

```bash
git add transcribe_youtubh.sh
git commit -m "feat: add summary_lang and cli_tool arguments"
```

---

### Task 2: Extract timestamp into a variable

**Files:**
- Modify: `transcribe_youtubh.sh:17` (the `OUTPUT_FILE` line)

- [ ] **Step 1: Replace the OUTPUT_FILE line to use a shared timestamp**

Replace:

```bash
OUTPUT_FILE="./transcript_$(date +%s).txt"
```

With:

```bash
TIMESTAMP=$(date +%s)
TRANSCRIPT_FILE="./transcript_${TIMESTAMP}.txt"
SUMMARY_FILE="./summary_${TIMESTAMP}.txt"
```

- [ ] **Step 2: Update all references from OUTPUT_FILE to TRANSCRIPT_FILE**

In the `echo "$TEXT" > "$OUTPUT_FILE"` line, replace `$OUTPUT_FILE` with `$TRANSCRIPT_FILE`.

In the final `echo "$OUTPUT_FILE"` line, replace `$OUTPUT_FILE` with `$TRANSCRIPT_FILE`.

- [ ] **Step 3: Test that transcription still works end-to-end**

Run: `bash transcribe_youtubh.sh "https://www.youtube.com/watch?v=TEST" zh`
Expected: Either a `transcript_<timestamp>.txt` file is created (if the API is reachable) or an error from the API. The script should not have syntax errors.

- [ ] **Step 4: Commit**

```bash
git add transcribe_youtubh.sh
git commit -m "refactor: extract timestamp for paired output files"
```

---

### Task 3: Add the summarization step

**Files:**
- Modify: `transcribe_youtubh.sh` — add summarization logic after the transcript is saved

- [ ] **Step 1: Add the summarization function and call it**

After the line `echo "$TEXT" > "$TRANSCRIPT_FILE"`, and before the final `echo` that prints the file path, insert:

```bash
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
```

- [ ] **Step 2: Update the final echo to print the transcript path before the summary block**

The success block should now look like this in full:

```bash
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
```

- [ ] **Step 3: Verify the complete script has no syntax errors**

Run: `bash -n transcribe_youtubh.sh`
Expected: No output (no syntax errors).

- [ ] **Step 4: Test summarization with an existing transcript file**

Run a quick smoke test by piping known text into the claude CLI:

```bash
echo "This is a test transcript about kubernetes" | claude -p "用繁體中文摘要以下影片逐字稿"
```

Expected: A Traditional Chinese summary is returned.

- [ ] **Step 5: Commit**

```bash
git add transcribe_youtubh.sh
git commit -m "feat: add auto-summarization via LLM CLI after transcription"
```

---

### Final Script (reference)

The completed `transcribe_youtubh.sh` should look like:

```bash
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
```
