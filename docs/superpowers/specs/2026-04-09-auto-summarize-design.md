# Auto-Summarize Transcription

## Overview

Modify `transcribe_youtubh.sh` to automatically summarize the transcript using an LLM CLI tool after transcription completes.

## Interface

```
transcribe_youtubh.sh "YOUTUBE_URL" [transcription_lang] [summary_lang] [cli_tool]
```

| Argument | Position | Default | Examples |
|----------|----------|---------|----------|
| `YOUTUBE_URL` | 1 (required) | — | YouTube URL |
| `transcription_lang` | 2 | `zh` | `en`, `zh`, `ja` |
| `summary_lang` | 3 | `zh-TW` | `en`, `zh-TW`, `ja` |
| `cli_tool` | 4 | `claude` | `claude`, `codex`, `gemini` |

## Output Files

Both files share the same timestamp so they pair up:

- `transcript_<timestamp>.txt` — raw transcription (existing behavior)
- `summary_<timestamp>.txt` — LLM-generated summary

## Flow

1. Transcribe via existing API call (unchanged)
2. Save transcript to `transcript_<timestamp>.txt` (unchanged)
3. Pipe transcript text into chosen CLI tool with a language-specific summarization prompt
4. Save summary output to `summary_<timestamp>.txt`
5. Print both file paths to stdout

## Summarization Prompt

Language-specific prompts:

- `zh-TW`: "用繁體中文摘要以下影片逐字稿"
- `en`: "Summarize the following video transcript in English"
- Other: "Summarize the following video transcript in {lang}"

## CLI Invocation

| Tool | Command |
|------|---------|
| `claude` | `echo "$TEXT" \| claude -p "<prompt>"` |
| `codex` | `echo "$TEXT" \| codex -q "<prompt>"` |
| `gemini` | `echo "$TEXT" \| gemini -p "<prompt>"` |

## Error Handling

- If the CLI tool is not installed or the summarization command fails, print an error to stderr but **do not** fail the script — the transcript file is still preserved.
- Transcription and summarization are independent: a summarization failure does not invalidate the transcription.

## Scope

- Modify the single existing script file only
- No new dependencies beyond the CLI tools themselves
- No changes to the transcription API call
