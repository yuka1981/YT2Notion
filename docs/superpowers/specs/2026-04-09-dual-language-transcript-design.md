# Dual-Language Full Transcript

## Overview

Add a dual-language side-by-side display in the "Full Transcript" toggle section of the Notion page. The original transcript appears on the left column and the Traditional Chinese translation on the right, displayed as Notion table(s).

## When It Applies

- **Dual-language**: When the transcript language (`--lang`) is NOT a Traditional Chinese variant (`zh-TW`, `zh-Hant`, `zh-HK`)
- **Single-language**: When `--lang` is a Traditional Chinese variant, keep the current behavior (plain paragraph blocks inside the toggle heading)

Language normalization: treat `zh-TW`, `zh-Hant`, and `zh-HK` as Traditional Chinese (single-language path). All other values including `zh` (Simplified Chinese) trigger the dual-language path.

## Flow

1. After transcription, check if `lang` is NOT a Traditional Chinese variant
2. If dual-language needed:
   a. Split transcript on original line breaks (as delivered by the transcription API — short phrase-per-line format)
   b. Filter out empty lines
   c. Translate in batches via LLM (up to 50 lines per batch)
   d. Zip original + translated lines into 2-column Notion table(s), chunked at 99 data rows per table
3. If single-language: keep current behavior (paragraph blocks)

## Line Splitting

Use the original line breaks from the transcription API output. Do NOT join lines into continuous text and re-split by sentence. The transcription API already outputs short, natural phrase-per-line format (subtitle-style), which is ideal for table rows.

- Split on `\n`
- Trim whitespace from each line
- Discard empty lines

## LLM Translation

New method in `LlmClient`:

```ruby
llm_client.translate_sentences(sentences, target_lang)
# Input: ["line 1", "line 2", ...]
# Output: ["翻譯 1", "翻譯 2", ...]
```

### Batched Translation

Translate in batches of up to 50 lines to improve reliability:

1. Split the sentences array into chunks of 50
2. For each batch, send to the LLM with numbered lines for alignment:

**Prompt format:**
```
將以下編號的每一行翻譯成繁體中文。保持相同的編號和行數，每行一個翻譯。只輸出翻譯結果，保留編號格式。

1. 语言暴力无处不在
2. 只要有人开口说话的地方
3. 很快就出现争吵
```

**Expected output:**
```
1. 語言暴力無處不在
2. 只要有人開口說話的地方
3. 很快就出現爭吵
```

3. Parse output by line number prefix (`/^\d+\.\s*/`)
4. If a batch's output line count doesn't match input: retry once
5. If retry also fails: raise `LlmClient::Error` (caller handles fallback)

The method returns the full array of translated lines (all batches concatenated).

### Prompts

- Default: "將以下編號的每一行翻譯成繁體中文。保持相同的編號和行數，每行一個翻譯。只輸出翻譯結果，保留編號格式。"
- For non-zh-TW target (future extensibility): "Translate each numbered line to {target_lang}. Keep the same numbering and line count. Output only translations, preserving the number format."

## Notion Page Structure

### When dual-language (lang is not Traditional Chinese)

The table is chunked into multiple tables if there are more than 99 data rows, because Notion limits table children to 100 rows (1 header + 99 data).

```
> Full Transcript (toggle heading, is_toggleable: true)
  table (2 columns, max 100 rows):     # table 1
    has_column_header: true
    has_row_header: false
    children:
      table_row: ["Original", "繁體中文"]     # header row
      table_row: ["line 1", "翻譯 1"]
      table_row: ["line 2", "翻譯 2"]
      ... (up to 99 data rows)
  table (2 columns):                     # table 2 (if needed)
    has_column_header: true
    children:
      table_row: ["Original (cont.)", "繁體中文 (cont.)"]
      table_row: ["line 100", "翻譯 100"]
      ...
```

### When single-language (Traditional Chinese variant)

No change from current behavior:

```
> Full Transcript (toggle heading)
  paragraph blocks with transcript text
```

### Rich Text Cell Limit

Each table cell's text must not exceed 2000 characters per rich_text object. If a line exceeds 2000 chars, split it into multiple rich_text objects within the same cell (same approach as existing `split_text` in NotionClient).

## Code Changes

### lib/llm_client.rb

Add `translate_sentences(sentences, target_lang)` method:
- Splits sentences into batches of 50
- Numbers each line in the batch (1-indexed)
- Sends each batch to LLM with numbered translation prompt
- Parses output by stripping number prefixes
- Validates line count per batch, retries once on mismatch
- If retry fails: raises `LlmClient::Error`
- Returns concatenated array of all translated lines

Add private helper `TRADITIONAL_CHINESE_LANGS` constant:
```ruby
TRADITIONAL_CHINESE_LANGS = %w[zh-TW zh-Hant zh-HK].freeze
```

### lib/notion_client.rb

Update `create_page` signature to accept optional `translated_sentences:` and `sentences:` parameters (default `nil`).

Update `build_children`:
- When `translated_sentences` is provided: build table block(s) inside the toggle heading
- When `translated_sentences` is nil: keep current paragraph blocks behavior

New private method `transcript_table_blocks(sentences, translated_sentences)`:
- Returns an array of `table` blocks (1 or more)
- Each table has `table_width: 2`, `has_column_header: true`
- Chunks data rows at 99 per table
- Each table gets its own header row
- Cell text uses `split_text` for the 2000-char limit

### transcribe.rb

- After transcription, check if `lang` is not in Traditional Chinese variants
- If dual-language:
  1. Split transcript on `\n`, filter empty lines
  2. Call `llm.translate_sentences(lines, "zh-TW")`
  3. Pass `sentences:` and `translated_sentences:` to `create_page`
- Wrap translation in a rescue block: on `LlmClient::Error`, print warning, proceed without translation (single-language fallback)

## Error Handling

- **Translation fails** (LLM error, CLI not found): Print warning to stderr, fall back to single-language paragraph blocks
- **Line count mismatch after retry**: Raise `LlmClient::Error`, caught by transcribe.rb as fallback
- **Notion API failure**: Existing behavior (WARNING, keep local files)
- Transcript and summary files are always saved regardless of translation success

## Edge Cases

- **Very long transcripts (>500 lines)**: Handled by batched translation (50 lines/batch) + chunked tables (99 rows/table)
- **Lines with no text after trim**: Discarded before translation
- **Single-line transcript**: Produces a table with 1 header + 1 data row (valid)
- **Lines > 2000 chars**: Split into multiple rich_text objects within the cell
- **`--lang zh`**: Simplified Chinese — triggers dual-language (translated to Traditional Chinese)
- **`--lang zh-TW`/`zh-Hant`/`zh-HK`**: Traditional Chinese variants — single-language path, no translation
