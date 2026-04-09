# Bilingual Transcript Refactor

## Problem

The current bilingual transcript renders as a 2-column Notion table with one row per transcript line fragment. Each row contains a tiny phrase (e.g., "如果我告诉你"), making it hard to read as continuous text.

## Solution

Replace the sentence-by-sentence table with two stacked, collapsible sections inside the "Full Transcript" toggle. Use the LLM to merge raw transcript lines into natural paragraphs before translating.

## Pipeline Flow

### Current

```
raw transcript → split by newlines → translate line-by-line (numbered, batched) → Notion 2-column table
```

### New

```
raw transcript → split by newlines → LLM merges into paragraphs → translate each paragraph → Notion stacked toggles
```

## LLM Changes (`lib/llm_client.rb`)

### Remove

- `translate_sentences` (public)
- `translate_batch` (private)
- Numbered-line translation approach

### Add

**`merge_to_paragraphs(lines)`**

- Takes an array of raw transcript lines (strings).
- Sends lines to the LLM in batches of `TRANSLATION_BATCH_SIZE` (50 lines).
- Prompt asks the LLM to merge the lines into natural paragraphs, separated by blank lines, without changing the wording.
- Returns a flat array of paragraph strings (collected across all batches).

**`translate_paragraphs(paragraphs, target_lang)`**

- Takes an array of paragraph strings.
- Translates each paragraph with one LLM call per paragraph.
- Prompt: "Translate this into {target_lang}. Output only the translation."
- Returns an array of translated paragraph strings, same length as input.

## Notion Changes (`lib/notion_client.rb`)

### Remove

- `transcript_table_blocks` method
- `table_row_block` method
- `rich_text_cell` method
- `MAX_TABLE_DATA_ROWS` constant

### Change: `build_children`

When bilingual data is present, replace the single toggle heading with table blocks:

**Old:**
```ruby
children << toggle_heading_block("Full Transcript", transcript_table_blocks(sentences, translated_sentences))
```

**New:** Build a "Full Transcript" toggle heading_2 containing two sub-sections:

1. **"Original Transcript"** — a non-toggleable heading_3 (always visible when parent is open), followed by toggle blocks for each original paragraph.
2. **"繁體中文"** — a toggle heading_3 (collapsed by default), containing toggle blocks for each translated paragraph.

### Notion Block Structure

```
heading_2 (toggleable): "Full Transcript"
  children:
    heading_3 (non-toggleable): "Original Transcript"
    toggle block: paragraph 1 text
    toggle block: paragraph 2 text
    ...
    heading_3 (toggleable): "繁體中文"
      children:
        toggle block: translated paragraph 1 text
        toggle block: translated paragraph 2 text
        ...
```

Each paragraph is rendered as a Notion `toggle` block (collapsible), allowing readers to fold paragraphs they have already read. Notion requires toggle blocks to have at least one child — use an empty paragraph block as the child.

### Keep

- `text_blocks` and `split_text` — reused for the single-language fallback and for building content within toggle blocks.

## Orchestration Changes (`transcribe.rb`)

### Current

```ruby
unless LlmClient::TRADITIONAL_CHINESE_LANGS.include?(options[:lang])
  lines = transcript.split("\n").map(&:strip).reject(&:empty?)
  translated_sentences = llm.translate_sentences(lines, "zh-TW")
  sentences = lines
end
```

### New

```ruby
unless LlmClient::TRADITIONAL_CHINESE_LANGS.include?(options[:lang])
  lines = transcript.split("\n").map(&:strip).reject(&:empty?)
  paragraphs = llm.merge_to_paragraphs(lines)
  translated_paragraphs = llm.translate_paragraphs(paragraphs, "zh-TW")
end
```

Pass `paragraphs` and `translated_paragraphs` to `NotionClient#create_page` instead of `sentences` and `translated_sentences`. Rename the keyword arguments accordingly.

Same graceful fallback: if merge or translate fails, warn and fall back to single-language transcript.

## Test Changes

### `spec/llm_client_spec.rb`

- Remove tests for `translate_sentences` and `translate_batch`.
- Add tests for `merge_to_paragraphs`: verify batching, verify output is an array of paragraph strings.
- Add tests for `translate_paragraphs`: verify one call per paragraph, verify output array matches input length.

### `spec/notion_client_spec.rb`

- Remove table block assertions.
- Add assertions for the new structure: "Full Transcript" toggle containing a heading_3 "Original Transcript" + toggle blocks, then a toggle heading_3 "繁體中文" + toggle blocks.

### `spec/transcribe_spec.rb`

- Update integration flow to call `merge_to_paragraphs` and `translate_paragraphs`.
- Verify the new keyword arguments passed to `NotionClient#create_page`.

## Out of Scope

- yt-dlp transcript download (separate follow-up spec)
- Changes to title, summary, or detail note generation
- Changes to single-language (non-bilingual) transcript flow
