# YouTube Transcription + Notion Pipeline

Transcribe YouTube videos, generate AI-powered summaries and structured notes, and publish everything to a Notion database -- with dual-language transcript support.

## What It Does

1. **Transcribes** a YouTube video via a transcription API
2. **Generates** a title, summary, and structured detail notes using an LLM CLI tool
3. **Translates** the transcript to Traditional Chinese (if the source is not already Traditional Chinese)
4. **Saves** transcript and summary to local files
5. **Publishes** a Notion page with:
   - Embedded YouTube video
   - Summary (with proper Notion formatting: headings, lists, tables, bold, etc.)
   - Detail notes (structured with headings, bullet points, sections)
   - Full transcript in a collapsible toggle (dual-language table when translated)

## Prerequisites

- **Ruby** 3.x
- **Bundler** (`gem install bundler`)
- An LLM CLI tool installed: [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex CLI](https://github.com/openai/codex), or [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- A running transcription API (expects a POST endpoint that accepts `{ url, lang }` and returns `{ text }`)
- A [Notion integration](https://www.notion.so/my-integrations) with access to your target database

## Setup

### 1. Install dependencies

```bash
bundle install
```

### 2. Configure environment variables

Create a `.env` file in the project root:

```bash
NOTION_API_KEY=ntn_your_notion_api_key
NOTION_DATABASE_ID=your_database_id
TRANSCRIBE_API_URL=http://your-transcription-api:9001/transcribe
```

| Variable | Description |
|----------|-------------|
| `NOTION_API_KEY` | Your Notion integration token (starts with `ntn_`) |
| `NOTION_DATABASE_ID` | The ID of your Notion database (from the database URL) |
| `TRANSCRIBE_API_URL` | The URL of your transcription API endpoint |

### 3. Notion database setup

Your Notion database needs these properties:

| Property | Type |
|----------|------|
| `Doc name` | Title |
| `Category` | Multi-select |

The script automatically creates a "YouTube Note" category option.

## Usage

```bash
ruby transcribe.rb "YOUTUBE_URL" [options]
```

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `--lang LANG` | `zh` | Transcription language |
| `--summary-lang LANG` | `zh-TW` | Summary and notes language |
| `--cli TOOL` | `claude` | LLM CLI tool: `claude`, `codex`, or `gemini` |
| `-h, --help` | | Show help |

### Examples

```bash
# Default: transcribe Chinese video, summarize in Traditional Chinese, use Claude
ruby transcribe.rb "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# English video, English summary
ruby transcribe.rb "https://www.youtube.com/watch?v=dQw4w9WgXcQ" --lang en --summary-lang en

# Japanese video, Traditional Chinese summary, use Gemini
ruby transcribe.rb "https://www.youtube.com/watch?v=dQw4w9WgXcQ" --lang ja --cli gemini

# Traditional Chinese video (no translation, single-language transcript)
ruby transcribe.rb "https://www.youtube.com/watch?v=dQw4w9WgXcQ" --lang zh-TW
```

### Output

On success, three lines are printed:

```
./transcript_1712649600.txt       # Local transcript file
./summary_1712649600.txt          # Local summary file
https://www.notion.so/page-id     # Notion page URL
```

## Dual-Language Transcript

When the transcript language is **not** Traditional Chinese (`zh-TW`, `zh-Hant`, `zh-HK`), the "Full Transcript" section in Notion displays a side-by-side table:

| Original | Traditional Chinese |
|----------|-------------|
| 语言暴力无处不在 | 語言暴力無處不在 |
| 只要有人开口说话的地方 | 只要有人開口說話的地方 |

When the transcript is already in Traditional Chinese, it displays as plain text (no translation needed).

Translation is done in batches of 50 lines with automatic retry. If translation fails, the script falls back to a single-language transcript gracefully.

## Notion Page Structure

```
[Embedded YouTube Video]

## Summary
AI-generated summary with formatted headings, lists, tables...

---

## Detail Note
Structured notes with sections, key takeaways, bullet points...

---

> Full Transcript (collapsible)
  | Original | Traditional Chinese |
  | ...      | ...                 |
```

## Project Structure

```
transcribe.rb              # CLI entry point
lib/
  transcriber.rb           # Transcription API client
  llm_client.rb            # LLM CLI tool wrapper (claude/codex/gemini)
  notion_client.rb         # Notion API client (page creation, block building)
  markdown_to_notion.rb    # Markdown to Notion block converter
spec/
  spec_helper.rb           # RSpec + WebMock config
  transcriber_spec.rb      # Transcriber tests
  llm_client_spec.rb       # LlmClient tests
  notion_client_spec.rb    # NotionClient tests
  markdown_to_notion_spec.rb  # Markdown converter tests
```

## Running Tests

```bash
bundle exec rspec
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Transcription API fails | Exits with error, no files created |
| LLM CLI fails (title/summary/notes) | Exits with error, transcript file preserved |
| Translation fails | Warning printed, falls back to single-language transcript |
| Notion API fails | Warning printed, local files preserved |
| Missing environment variables | Exits immediately with list of missing vars |
