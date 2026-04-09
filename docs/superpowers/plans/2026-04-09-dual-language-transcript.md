# Dual-Language Full Transcript Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add dual-language side-by-side transcript display in Notion using a table with original + Traditional Chinese translation, with batched LLM translation and proper chunking for Notion API limits.

**Architecture:** Add `translate_sentences` to LlmClient (batched, numbered lines). Add `transcript_table_blocks` to NotionClient (chunked tables, 99 rows max). Update `create_page` to accept optional translation data. The CLI orchestrates: split lines, translate if needed, pass to Notion.

**Tech Stack:** Ruby, RSpec, WebMock, Open3 (CLI tools), Notion API v2022-06-28

---

### File Structure

```
lib/
  llm_client.rb            # Add: TRADITIONAL_CHINESE_LANGS, translate_sentences
  notion_client.rb         # Add: transcript_table_blocks, update create_page/build_children
spec/
  llm_client_spec.rb       # Add: translate_sentences tests
  notion_client_spec.rb    # Add: dual-language table tests
transcribe.rb              # Add: translation logic + fallback
```

---

### Task 1: Add TRADITIONAL_CHINESE_LANGS constant and translate_sentences to LlmClient

**Files:**
- Modify: `lib/llm_client.rb`
- Modify: `spec/llm_client_spec.rb`

- [ ] **Step 1: Write failing tests for translate_sentences**

Add to `spec/llm_client_spec.rb`:

```ruby
  describe "::TRADITIONAL_CHINESE_LANGS" do
    it "includes zh-TW, zh-Hant, zh-HK" do
      expect(LlmClient::TRADITIONAL_CHINESE_LANGS).to contain_exactly("zh-TW", "zh-Hant", "zh-HK")
    end
  end

  describe "#translate_sentences" do
    it "translates a batch of sentences with numbered lines" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("1. 語言暴力無處不在\n2. 只要有人開口說話的地方")

      result = client.translate_sentences(["语言暴力无处不在", "只要有人开口说话的地方"], "zh-TW")
      expect(result).to eq(["語言暴力無處不在", "只要有人開口說話的地方"])
    end

    it "sends numbered lines in the prompt input" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("1. Line one\n2. Line two")

      client.translate_sentences(["Line one", "Line two"], "zh-TW")
      expect(client).to have_received(:generate) do |prompt, input|
        expect(input).to include("1. Line one")
        expect(input).to include("2. Line two")
      end
    end

    it "handles batches of more than 50 lines" do
      client = LlmClient.new("claude")
      lines = (1..75).map { |i| "Line #{i}" }

      call_count = 0
      allow(client).to receive(:generate) do |prompt, input|
        call_count += 1
        numbered = input.lines.map(&:strip).reject(&:empty?)
        numbered.map { |l| l }.join("\n")
      end

      result = client.translate_sentences(lines, "zh-TW")
      expect(call_count).to eq(2) # 50 + 25
      expect(result.length).to eq(75)
    end

    it "retries once on line count mismatch then raises" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate)
        .and_return("1. Only one line")

      expect {
        client.translate_sentences(["line 1", "line 2", "line 3"], "zh-TW")
      }.to raise_error(LlmClient::Error, /line count mismatch/)
    end

    it "uses zh-TW prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("1. 翻譯")

      client.translate_sentences(["hello"], "zh-TW")
      expect(client).to have_received(:generate) do |prompt, _input|
        expect(prompt).to include("翻譯成繁體中文")
      end
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/reid/youtube && bundle exec rspec spec/llm_client_spec.rb`
Expected: FAIL — `undefined constant TRADITIONAL_CHINESE_LANGS` / `undefined method translate_sentences`

- [ ] **Step 3: Implement translate_sentences**

Add to `lib/llm_client.rb` after the `SUPPORTED_TOOLS` constant:

```ruby
  TRADITIONAL_CHINESE_LANGS = %w[zh-TW zh-Hant zh-HK].freeze
  TRANSLATION_BATCH_SIZE = 50
```

Add after `generate_detail_note`:

```ruby
  def translate_sentences(sentences, target_lang)
    results = []
    sentences.each_slice(TRANSLATION_BATCH_SIZE) do |batch|
      translated = translate_batch(batch, target_lang)
      results.concat(translated)
    end
    results
  end

  private
```

(Move the existing `private` keyword down if needed — `translate_sentences` must be public.)

Add as a private method:

```ruby
  def translate_batch(batch, target_lang, retries: 1)
    numbered_input = batch.each_with_index.map { |line, i| "#{i + 1}. #{line}" }.join("\n")

    prompt = if target_lang == "zh-TW"
               "將以下編號的每一行翻譯成繁體中文。保持相同的編號和行數，每行一個翻譯。只輸出翻譯結果，保留編號格式。"
             else
               "Translate each numbered line to #{target_lang}. Keep the same numbering and line count. Output only translations, preserving the number format."
             end

    output = generate(prompt, numbered_input)
    parsed = output.lines.map { |l| l.strip.sub(/^\d+\.\s*/, "") }.reject(&:empty?)

    if parsed.length != batch.length
      if retries > 0
        return translate_batch(batch, target_lang, retries: retries - 1)
      end
      raise Error, "Translation line count mismatch: expected #{batch.length}, got #{parsed.length}"
    end

    parsed
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/reid/youtube && bundle exec rspec spec/llm_client_spec.rb`
Expected: All tests pass.

- [ ] **Step 5: Run full suite**

Run: `cd /home/reid/youtube && bundle exec rspec`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/llm_client.rb spec/llm_client_spec.rb
git commit -m "feat: add batched translate_sentences to LlmClient"
```

---

### Task 2: Add dual-language table support to NotionClient

**Files:**
- Modify: `lib/notion_client.rb`
- Modify: `spec/notion_client_spec.rb`

- [ ] **Step 1: Write failing tests for dual-language table**

Add to `spec/notion_client_spec.rb` inside the `describe "#create_page"` block:

```ruby
    it "builds a dual-language table when sentences and translated_sentences are provided" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "full text",
        sentences: ["hello", "world"],
        translated_sentences: ["你好", "世界"]
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        children = body["children"]
        toggle = children.last

        toggle["heading_2"]["is_toggleable"] == true &&
          toggle["heading_2"]["children"][0]["type"] == "table" &&
          toggle["heading_2"]["children"][0]["table"]["table_width"] == 2 &&
          toggle["heading_2"]["children"][0]["table"]["has_column_header"] == true
      }
    end

    it "includes header row and data rows in dual-language table" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "full text",
        sentences: ["hello"],
        translated_sentences: ["你好"]
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        toggle = body["children"].last
        table = toggle["heading_2"]["children"][0]
        rows = table["table"]["children"]

        rows.length == 2 &&
          rows[0]["table_row"]["cells"][0][0]["text"]["content"] == "Original" &&
          rows[0]["table_row"]["cells"][1][0]["text"]["content"] == "繁體中文" &&
          rows[1]["table_row"]["cells"][0][0]["text"]["content"] == "hello" &&
          rows[1]["table_row"]["cells"][1][0]["text"]["content"] == "你好"
      }
    end

    it "chunks dual-language table at 99 data rows" do
      sentences = (1..150).map { |i| "line #{i}" }
      translated = (1..150).map { |i| "翻譯 #{i}" }

      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "full text",
        sentences: sentences,
        translated_sentences: translated
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        toggle = body["children"].last
        tables = toggle["heading_2"]["children"]

        tables.length == 2 &&
          tables[0]["type"] == "table" &&
          tables[0]["table"]["children"].length == 100 &&  # 1 header + 99 data
          tables[1]["type"] == "table" &&
          tables[1]["table"]["children"].length == 52       # 1 header + 51 data
      }
    end

    it "falls back to paragraph blocks when no translation provided" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "The full transcript content"
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        toggle = body["children"].last

        toggle["heading_2"]["children"][0]["type"] == "paragraph"
      }
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/reid/youtube && bundle exec rspec spec/notion_client_spec.rb`
Expected: FAIL — `unknown keyword: :sentences`

- [ ] **Step 3: Implement dual-language table in NotionClient**

Update `create_page` signature in `lib/notion_client.rb`:

```ruby
  def create_page(title:, category:, youtube_url:, summary:, detail_note:, transcript:, sentences: nil, translated_sentences: nil)
    children = build_children(youtube_url, summary, detail_note, transcript, sentences, translated_sentences)
```

Update `build_children` signature and the transcript line:

```ruby
  def build_children(youtube_url, summary, detail_note, transcript, sentences, translated_sentences)
    children = []
    children << video_block(youtube_url)
    children << heading_block("Summary")
    children.concat(MarkdownToNotion.convert(summary))
    children << divider_block
    children << heading_block("Detail Note")
    children.concat(MarkdownToNotion.convert(detail_note))
    children << divider_block

    if sentences && translated_sentences
      children << toggle_heading_block("Full Transcript", transcript_table_blocks(sentences, translated_sentences))
    else
      children << toggle_heading_block("Full Transcript", text_blocks(transcript))
    end

    children
  end
```

Add new private method `transcript_table_blocks`:

```ruby
  MAX_TABLE_DATA_ROWS = 99

  def transcript_table_blocks(sentences, translated_sentences)
    pairs = sentences.zip(translated_sentences)
    tables = []

    pairs.each_slice(MAX_TABLE_DATA_ROWS) do |chunk|
      header = table_row_block("Original", "繁體中文")
      data_rows = chunk.map { |orig, trans| table_row_block(orig, trans) }

      tables << {
        "object" => "block",
        "type" => "table",
        "table" => {
          "table_width" => 2,
          "has_column_header" => true,
          "has_row_header" => false,
          "children" => [header] + data_rows
        }
      }
    end

    tables
  end

  def table_row_block(cell1, cell2)
    {
      "object" => "block",
      "type" => "table_row",
      "table_row" => {
        "cells" => [
          rich_text_cell(cell1),
          rich_text_cell(cell2)
        ]
      }
    }
  end

  def rich_text_cell(text)
    split_text(text).map do |chunk|
      { "type" => "text", "text" => { "content" => chunk } }
    end
  end
```

Also add the `MAX_TABLE_DATA_ROWS = 99` constant near the other constants at the top of the class.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/reid/youtube && bundle exec rspec spec/notion_client_spec.rb`
Expected: All tests pass.

- [ ] **Step 5: Run full suite**

Run: `cd /home/reid/youtube && bundle exec rspec`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/notion_client.rb spec/notion_client_spec.rb
git commit -m "feat: add dual-language transcript table to NotionClient"
```

---

### Task 3: Update CLI entry point with translation orchestration

**Files:**
- Modify: `transcribe.rb`

- [ ] **Step 1: Update transcribe.rb to add translation logic**

Replace the `# Step 3: Upload to Notion` section (lines 62-71) with:

```ruby
  # Step 2.5: Translate transcript if not Traditional Chinese
  sentences = nil
  translated_sentences = nil
  unless LlmClient::TRADITIONAL_CHINESE_LANGS.include?(options[:lang])
    begin
      lines = transcript.split("\n").map(&:strip).reject(&:empty?)
      translated_sentences = llm.translate_sentences(lines, "zh-TW")
      sentences = lines
    rescue LlmClient::Error => e
      $stderr.puts "WARNING: Translation failed, using single-language transcript: #{e.message}"
      sentences = nil
      translated_sentences = nil
    end
  end

  # Step 3: Upload to Notion
  notion = NotionClient.new(ENV["NOTION_API_KEY"], ENV["NOTION_DATABASE_ID"])
  page_url = notion.create_page(
    title: title,
    category: "YouTube Note",
    youtube_url: url,
    summary: summary,
    detail_note: detail_note,
    transcript: transcript,
    sentences: sentences,
    translated_sentences: translated_sentences
  )
  puts page_url
```

- [ ] **Step 2: Verify syntax**

Run: `cd /home/reid/youtube && ruby -c transcribe.rb`
Expected: `Syntax OK`

- [ ] **Step 3: Verify help still works**

Run: `cd /home/reid/youtube && ruby transcribe.rb --help`
Expected: Usage banner displayed.

- [ ] **Step 4: Commit**

```bash
git add transcribe.rb
git commit -m "feat: add dual-language translation orchestration to CLI"
```

---

### Task 4: Run full test suite and verify

- [ ] **Step 1: Run full suite**

Run: `cd /home/reid/youtube && bundle exec rspec`
Expected: All tests pass.

- [ ] **Step 2: Verify all Ruby files have valid syntax**

Run: `cd /home/reid/youtube && ruby -c transcribe.rb && ruby -c lib/transcriber.rb && ruby -c lib/llm_client.rb && ruby -c lib/notion_client.rb && ruby -c lib/markdown_to_notion.rb`
Expected: `Syntax OK` for each.
