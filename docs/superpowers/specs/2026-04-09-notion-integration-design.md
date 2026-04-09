# YouTube Transcription + Notion Pipeline (Ruby)

## Overview

Rewrite the YouTube transcription tool in Ruby with RSpec (TDD). The tool transcribes YouTube videos via an existing API, generates a title + summary + structured detail notes via CLI LLM tools, saves files locally, and publishes everything to a Notion database.

## Interface

```
ruby transcribe.rb "YOUTUBE_URL" [--lang zh] [--summary-lang zh-TW] [--cli claude]
```

| Argument | Default | Description |
|----------|---------|-------------|
| `YOUTUBE_URL` | (required) | YouTube video URL |
| `--lang` | `zh` | Transcription language |
| `--summary-lang` | `zh-TW` | Summary/notes language |
| `--cli` | `claude` | CLI tool: `claude`, `codex`, `gemini` |

## Flow

1. **Validate** — Check required env vars (`NOTION_API_KEY`, `NOTION_DATABASE_ID`, `TRANSCRIBE_API_URL`) are present. Fail fast if missing.
2. **Transcribe** — POST to existing API at `TRANSCRIBE_API_URL` with URL and language. Extract text from JSON response.
3. **Save transcript** — Write raw transcript to `transcript_<timestamp>.txt`.
4. **LLM calls** (3 separate CLI invocations):
   - **Title**: Generate a concise title from the transcript
   - **Summary**: Generate a summary in the target language
   - **Detail note**: Generate an organized version with headings, key points, bullet points in the target language
5. **Save summary** — Write summary to `summary_<timestamp>.txt`.
6. **Upload to Notion** — Create a page in the Document Hub database with title, category, and structured body.

## Architecture

```
transcribe.rb              # CLI entry point (argument parsing, orchestration)
lib/
  transcriber.rb           # Calls the transcription API
  llm_client.rb            # Shells out to CLI tools (claude/codex/gemini)
  notion_client.rb         # Notion API integration (create page, build blocks)
spec/
  transcriber_spec.rb      # Tests for transcription API client
  llm_client_spec.rb       # Tests for CLI tool invocation
  notion_client_spec.rb    # Tests for Notion page creation
```

## Component Details

### transcribe.rb (entry point)

Parses arguments using `OptionParser`. Loads `.env`. Orchestrates the pipeline: transcribe -> LLM calls -> save files -> upload to Notion. Prints file paths and Notion page URL on success.

### lib/transcriber.rb

Single responsibility: call the transcription API.

- `Transcriber.new(api_url)`
- `transcriber.transcribe(url, lang)` -> returns transcript text
- Uses `net/http` for the POST request
- Parses JSON response, extracts `text` field
- Raises descriptive error on failure

### lib/llm_client.rb

Single responsibility: shell out to LLM CLI tools.

- `LlmClient.new(cli_tool)` — accepts `"claude"`, `"codex"`, `"gemini"`
- `llm_client.generate(prompt, input_text)` -> returns LLM output string
- CLI invocation:
  - `claude`: `echo "<input>" | claude -p "<prompt>"`
  - `codex`: `echo "<input>" | codex exec "<prompt>"`
  - `gemini`: `echo "<input>" | gemini -p "<prompt>"`
- Raises error if CLI tool not found or returns empty output

Three specific methods that call `generate` internally:

- `llm_client.generate_title(transcript)` -> short title string
- `llm_client.generate_summary(transcript, lang)` -> summary string
- `llm_client.generate_detail_note(transcript, lang)` -> structured notes string (markdown)

#### Prompts

Title prompt (always English instruction, output in summary language):
- `zh-TW`: "根據以下逐字稿，用繁體中文生成一個簡短的標題"
- `en`: "Generate a concise title for the following transcript"
- Other: "Generate a concise title for the following transcript in {lang}"

Summary prompt:
- `zh-TW`: "用繁體中文摘要以下影片逐字稿"
- `en`: "Summarize the following video transcript in English"
- Other: "Summarize the following video transcript in {lang}"

Detail note prompt:
- `zh-TW`: "用繁體中文將以下影片逐字稿整理成結構化筆記，包含標題、重點摘要、分段說明與要點列表"
- `en`: "Organize the following video transcript into structured notes with headings, key takeaways, sections, and bullet points in English"
- Other: "Organize the following video transcript into structured notes with headings, key takeaways, sections, and bullet points in {lang}"

### lib/notion_client.rb

Single responsibility: create pages in Notion via the API.

- `NotionClient.new(api_key, database_id)`
- `notion_client.create_page(title:, category:, summary:, detail_note:, transcript:)` -> returns page URL
- Uses `net/http` with `Notion-Version: 2022-06-28` header
- Constructs the page with Notion block API format

#### Notion Page Structure

Properties:
- **Doc name** (title): LLM-generated title
- **Category** (multi_select): `["YouTube Note"]`

Page body (children blocks):
1. `heading_2`: "Summary"
2. `paragraph` blocks: summary text (split into chunks if > 2000 chars per block, Notion API limit)
3. `divider`
4. `heading_2`: "Detail Note"
5. `paragraph` blocks: detail note text (split into chunks)
6. `divider`
7. `heading_2`: "Full Transcript"
8. `paragraph` blocks: full transcript text (split into chunks)

Note: Notion API limits children to 100 blocks per request. If content exceeds this, use `PATCH /v1/blocks/{block_id}/children` to append additional blocks after page creation.

## Dependencies

Gemfile:
```ruby
source "https://rubygems.org"

gem "dotenv"

group :test do
  gem "rspec"
  gem "webmock"
end
```

- `net/http` + `json` — stdlib, no gem needed for HTTP and JSON
- `dotenv` — load `.env` file
- `rspec` — testing framework
- `webmock` — stub HTTP requests in tests

No SDK gems. LLM calls go through CLI tools.

## Config

`.env` file:
```
NOTION_API_KEY=ntn_xxx
NOTION_DATABASE_ID=26b079b781cc80cd961bf2f601652cc8
TRANSCRIBE_API_URL=http://10.106.37.191:9001/transcribe
```

## Error Handling

- **Missing env vars** -> fail fast at startup with clear message listing which vars are missing
- **Transcription API failure** -> exit with error, no files created
- **LLM CLI failure** (tool not found, empty output) -> exit with error, transcript file is kept
- **Notion API failure** -> print error to stderr, but keep local files (transcript + summary)
- Each component raises specific errors with descriptive messages

## Output

On success, the script prints:
```
transcript_1234567890.txt
summary_1234567890.txt
https://www.notion.so/page-id
```

On partial success (Notion fails):
```
transcript_1234567890.txt
summary_1234567890.txt
WARNING: Failed to upload to Notion: <error message>
```
