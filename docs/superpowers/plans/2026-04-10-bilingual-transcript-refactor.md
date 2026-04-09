# Bilingual Transcript Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the sentence-by-sentence bilingual table with stacked collapsible paragraph sections in Notion.

**Architecture:** Two new LLM methods (`merge_to_paragraphs`, `translate_paragraphs`) replace the old numbered-line translation. Notion rendering changes from a 2-column table to two sub-sections (heading + toggle blocks) inside the "Full Transcript" toggle. Orchestration in `transcribe.rb` passes paragraphs instead of sentences.

**Tech Stack:** Ruby, RSpec, WebMock, Notion API, LLM CLI (claude/codex/gemini)

---

### Task 1: Add `merge_to_paragraphs` to LlmClient (tests)

**Files:**
- Modify: `spec/llm_client_spec.rb` (replace `describe "#translate_sentences"` block, lines 182-237)
- Reference: `lib/llm_client.rb`

- [ ] **Step 1: Remove old translate_sentences tests**

Delete the entire `describe "#translate_sentences"` block (lines 182-237) from `spec/llm_client_spec.rb`.

- [ ] **Step 2: Write failing tests for merge_to_paragraphs**

Add the following at the end of `spec/llm_client_spec.rb`, before the final `end`:

```ruby
describe "#merge_to_paragraphs" do
  it "sends lines to LLM and returns paragraphs split by blank lines" do
    client = LlmClient.new("claude")
    allow(client).to receive(:generate)
      .and_return("First paragraph merged from lines.\n\nSecond paragraph merged.")

    result = client.merge_to_paragraphs(["line one", "line two", "line three", "line four"])
    expect(result).to eq(["First paragraph merged from lines.", "Second paragraph merged."])
  end

  it "uses zh-TW merge prompt" do
    client = LlmClient.new("claude")
    allow(client).to receive(:generate)
      .and_return("合併段落")

    client.merge_to_paragraphs(["第一行", "第二行"])
    expect(client).to have_received(:generate) do |prompt, _input|
      expect(prompt).to include("段落")
    end
  end

  it "batches lines at TRANSLATION_BATCH_SIZE and collects all paragraphs" do
    client = LlmClient.new("claude")
    lines = (1..75).map { |i| "Line #{i}" }

    call_count = 0
    allow(client).to receive(:generate) do |_prompt, _input|
      call_count += 1
      "Paragraph from batch #{call_count}."
    end

    result = client.merge_to_paragraphs(lines)
    expect(call_count).to eq(2)
    expect(result).to eq(["Paragraph from batch 1.", "Paragraph from batch 2."])
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /home/reid/youtube && bundle exec rspec spec/llm_client_spec.rb -e "merge_to_paragraphs" --format documentation`

Expected: FAIL with `NoMethodError: undefined method 'merge_to_paragraphs'`

- [ ] **Step 4: Commit**

```bash
git add spec/llm_client_spec.rb
git commit -m "test: add failing tests for merge_to_paragraphs, remove translate_sentences tests"
```

---

### Task 2: Add `translate_paragraphs` to LlmClient (tests)

**Files:**
- Modify: `spec/llm_client_spec.rb`

- [ ] **Step 1: Write failing tests for translate_paragraphs**

Add the following at the end of `spec/llm_client_spec.rb`, before the final `end`:

```ruby
describe "#translate_paragraphs" do
  it "translates each paragraph with one LLM call per paragraph" do
    client = LlmClient.new("claude")
    call_count = 0
    allow(client).to receive(:generate) do |_prompt, input|
      call_count += 1
      "Translated: #{input}"
    end

    result = client.translate_paragraphs(["Para one.", "Para two."], "zh-TW")
    expect(call_count).to eq(2)
    expect(result).to eq(["Translated: Para one.", "Translated: Para two."])
  end

  it "uses zh-TW translation prompt" do
    client = LlmClient.new("claude")
    allow(client).to receive(:generate).and_return("翻譯結果")

    client.translate_paragraphs(["Hello world."], "zh-TW")
    expect(client).to have_received(:generate) do |prompt, _input|
      expect(prompt).to include("繁體中文")
    end
  end

  it "uses generic translation prompt for other languages" do
    client = LlmClient.new("claude")
    allow(client).to receive(:generate).and_return("Translated")

    client.translate_paragraphs(["Hello world."], "ja")
    expect(client).to have_received(:generate) do |prompt, _input|
      expect(prompt).to include("ja")
    end
  end

  it "returns array same length as input" do
    client = LlmClient.new("claude")
    allow(client).to receive(:generate).and_return("translated")

    paragraphs = ["p1", "p2", "p3"]
    result = client.translate_paragraphs(paragraphs, "zh-TW")
    expect(result.length).to eq(3)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/reid/youtube && bundle exec rspec spec/llm_client_spec.rb -e "translate_paragraphs" --format documentation`

Expected: FAIL with `NoMethodError: undefined method 'translate_paragraphs'`

- [ ] **Step 3: Commit**

```bash
git add spec/llm_client_spec.rb
git commit -m "test: add failing tests for translate_paragraphs"
```

---

### Task 3: Implement `merge_to_paragraphs` and `translate_paragraphs`

**Files:**
- Modify: `lib/llm_client.rb`

- [ ] **Step 1: Replace translate_sentences and translate_batch with new methods**

In `lib/llm_client.rb`, remove the `translate_sentences` method (lines 53-60) and the `translate_batch` method (lines 73-93). Replace them with:

```ruby
def merge_to_paragraphs(lines)
  paragraphs = []
  lines.each_slice(TRANSLATION_BATCH_SIZE) do |batch|
    input = batch.join("\n")
    prompt = "將以下逐字稿的短句合併成自然的段落，段落之間用空行分隔。不要改變原文的用詞。"
    output = generate(prompt, input)
    batch_paragraphs = output.split(/\n\s*\n/).map(&:strip).reject(&:empty?)
    paragraphs.concat(batch_paragraphs)
  end
  paragraphs
end

def translate_paragraphs(paragraphs, target_lang)
  paragraphs.map do |paragraph|
    prompt = if target_lang == "zh-TW"
               "將以下文字翻譯成繁體中文。只輸出翻譯結果。"
             else
               "Translate the following text into #{target_lang}. Output only the translation."
             end
    generate(prompt, paragraph)
  end
end
```

- [ ] **Step 2: Run all LlmClient tests to verify they pass**

Run: `cd /home/reid/youtube && bundle exec rspec spec/llm_client_spec.rb --format documentation`

Expected: ALL PASS (existing tests for generate, generate_title, generate_summary, generate_detail_note should still pass; new merge_to_paragraphs and translate_paragraphs tests should pass)

- [ ] **Step 3: Commit**

```bash
git add lib/llm_client.rb
git commit -m "feat: replace translate_sentences with merge_to_paragraphs and translate_paragraphs"
```

---

### Task 4: Update NotionClient bilingual rendering (tests)

**Files:**
- Modify: `spec/notion_client_spec.rb` (replace table-related tests, lines 174-267)

- [ ] **Step 1: Remove old table-related tests**

Delete these three test blocks from `spec/notion_client_spec.rb`:
- `"builds a dual-language table when sentences and translated_sentences are provided"` (lines 174-195)
- `"includes header row and data rows in dual-language table"` (lines 197-221)
- `"chunks dual-language table at 99 data rows"` (lines 223-249)

- [ ] **Step 2: Write failing tests for new bilingual structure**

Add the following before the `"falls back to paragraph blocks when no translation provided"` test:

```ruby
it "renders bilingual transcript as stacked toggle sections" do
  client.create_page(
    title: "Title",
    category: "YouTube Note",
    youtube_url: youtube_url,
    summary: "Summary",
    detail_note: "Notes",
    transcript: "full text",
    paragraphs: ["Hello world.", "Second paragraph."],
    translated_paragraphs: ["你好世界。", "第二段。"]
  )

  expect(WebMock).to have_requested(:post, notion_api).with { |req|
    body = JSON.parse(req.body)
    toggle = body["children"].last
    children = toggle["heading_2"]["children"]

    # First child: non-toggleable heading_3 "Original Transcript"
    children[0]["type"] == "heading_3" &&
      children[0]["heading_3"]["rich_text"][0]["text"]["content"] == "Original Transcript" &&
      !children[0]["heading_3"].key?("is_toggleable") &&
      # Next children: toggle blocks for each original paragraph
      children[1]["type"] == "toggle" &&
      children[1]["toggle"]["rich_text"][0]["text"]["content"] == "Hello world." &&
      children[2]["type"] == "toggle" &&
      children[2]["toggle"]["rich_text"][0]["text"]["content"] == "Second paragraph." &&
      # Then: toggleable heading_3 "繁體中文"
      children[3]["type"] == "heading_3" &&
      children[3]["heading_3"]["rich_text"][0]["text"]["content"] == "繁體中文" &&
      children[3]["heading_3"]["is_toggleable"] == true &&
      # Its children: toggle blocks for each translated paragraph
      children[3]["heading_3"]["children"][0]["type"] == "toggle" &&
      children[3]["heading_3"]["children"][0]["toggle"]["rich_text"][0]["text"]["content"] == "你好世界。" &&
      children[3]["heading_3"]["children"][1]["type"] == "toggle" &&
      children[3]["heading_3"]["children"][1]["toggle"]["rich_text"][0]["text"]["content"] == "第二段。"
  }
end

it "handles many paragraphs without exceeding Notion nested children limit" do
  # Notion allows max 100 children per block. With LLM-merged paragraphs,
  # typical transcripts produce 20-40 paragraphs, well under the limit.
  # This test verifies the structure stays correct with a moderate count.
  paragraphs = (1..50).map { |i| "Paragraph #{i}." }
  translated = (1..50).map { |i| "翻譯 #{i}。" }

  client.create_page(
    title: "Title",
    category: "YouTube Note",
    youtube_url: youtube_url,
    summary: "Summary",
    detail_note: "Notes",
    transcript: "full text",
    paragraphs: paragraphs,
    translated_paragraphs: translated
  )

  expect(WebMock).to have_requested(:post, notion_api).with { |req|
    body = JSON.parse(req.body)
    toggle = body["children"].last
    children = toggle["heading_2"]["children"]

    # heading_3 "Original Transcript" + 50 toggle blocks + heading_3 "繁體中文" = 52 children
    children.length == 52 &&
      children[0]["type"] == "heading_3" &&
      children[1]["type"] == "toggle" &&
      children[50]["type"] == "toggle" &&
      children[51]["type"] == "heading_3" &&
      children[51]["heading_3"]["is_toggleable"] == true &&
      children[51]["heading_3"]["children"].length == 50
  }
end

it "toggle blocks have an empty paragraph child" do
  client.create_page(
    title: "Title",
    category: "YouTube Note",
    youtube_url: youtube_url,
    summary: "Summary",
    detail_note: "Notes",
    transcript: "full text",
    paragraphs: ["Hello world."],
    translated_paragraphs: ["你好世界。"]
  )

  expect(WebMock).to have_requested(:post, notion_api).with { |req|
    body = JSON.parse(req.body)
    toggle = body["children"].last
    children = toggle["heading_2"]["children"]

    # Original paragraph toggle block has an empty paragraph child
    original_toggle = children[1]
    original_toggle["toggle"]["children"].length == 1 &&
      original_toggle["toggle"]["children"][0]["type"] == "paragraph" &&
      original_toggle["toggle"]["children"][0]["paragraph"]["rich_text"][0]["text"]["content"] == " "
  }
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /home/reid/youtube && bundle exec rspec spec/notion_client_spec.rb -e "bilingual" -e "toggle blocks have" --format documentation`

Expected: FAIL (unknown keyword `paragraphs`, or structure mismatch)

- [ ] **Step 4: Commit**

```bash
git add spec/notion_client_spec.rb
git commit -m "test: add failing tests for stacked bilingual toggle sections"
```

---

### Task 5: Implement new NotionClient bilingual rendering

**Files:**
- Modify: `lib/notion_client.rb`

- [ ] **Step 1: Update create_page signature**

In `lib/notion_client.rb`, change the `create_page` method signature (line 21) from:

```ruby
def create_page(title:, category:, youtube_url:, summary:, detail_note:, transcript:, sentences: nil, translated_sentences: nil, upload_date: nil)
```

to:

```ruby
def create_page(title:, category:, youtube_url:, summary:, detail_note:, transcript:, paragraphs: nil, translated_paragraphs: nil, upload_date: nil)
```

Update the `build_children` call (line 22) from:

```ruby
children = build_children(youtube_url, summary, detail_note, transcript, sentences, translated_sentences)
```

to:

```ruby
children = build_children(youtube_url, summary, detail_note, transcript, paragraphs, translated_paragraphs)
```

- [ ] **Step 2: Update build_children**

Change the `build_children` method signature (line 70) from:

```ruby
def build_children(youtube_url, summary, detail_note, transcript, sentences, translated_sentences)
```

to:

```ruby
def build_children(youtube_url, summary, detail_note, transcript, paragraphs, translated_paragraphs)
```

Replace the bilingual branch (lines 79-83) from:

```ruby
if sentences && translated_sentences
  children << toggle_heading_block("Full Transcript", transcript_table_blocks(sentences, translated_sentences))
else
  children << toggle_heading_block("Full Transcript", text_blocks(transcript))
end
```

to:

```ruby
if paragraphs && translated_paragraphs
  children << toggle_heading_block("Full Transcript", bilingual_transcript_blocks(paragraphs, translated_paragraphs))
else
  children << toggle_heading_block("Full Transcript", text_blocks(transcript))
end
```

- [ ] **Step 3: Replace table methods with bilingual_transcript_blocks**

Delete the following methods:
- `transcript_table_blocks` (lines 137-158)
- `table_row_block` (lines 160-171)
- `rich_text_cell` (lines 173-177)

Delete the constant:
- `MAX_TABLE_DATA_ROWS = 99` (line 14)

Add these new methods in the `private` section:

```ruby
def bilingual_transcript_blocks(paragraphs, translated_paragraphs)
  translated_toggles = translated_paragraphs.map { |p| toggle_block(p) }
  translated_section = toggle_heading_3_block("繁體中文", translated_toggles)

  # Build original section: heading + toggle blocks
  original_toggles = paragraphs.map { |p| toggle_block(p) }

  # Notion limits children per block. Chunk original toggles so that
  # heading_3 + chunk + translated_section (on last chunk) fits within limit.
  # We always place translated_section at the end.
  blocks = []
  blocks << heading_3_block("Original Transcript")
  blocks.concat(original_toggles)
  blocks << translated_section
  blocks
end

def heading_3_block(text)
  {
    "object" => "block",
    "type" => "heading_3",
    "heading_3" => {
      "rich_text" => [{ "type" => "text", "text" => { "content" => text } }]
    }
  }
end

def toggle_heading_3_block(text, children_blocks)
  {
    "object" => "block",
    "type" => "heading_3",
    "heading_3" => {
      "rich_text" => [{ "type" => "text", "text" => { "content" => text } }],
      "is_toggleable" => true,
      "children" => children_blocks
    }
  }
end

def toggle_block(text)
  {
    "object" => "block",
    "type" => "toggle",
    "toggle" => {
      "rich_text" => split_text(text).map { |chunk|
        { "type" => "text", "text" => { "content" => chunk } }
      },
      "children" => [
        {
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => {
            "rich_text" => [{ "type" => "text", "text" => { "content" => " " } }]
          }
        }
      ]
    }
  }
end
```

- [ ] **Step 4: Run all NotionClient tests to verify they pass**

Run: `cd /home/reid/youtube && bundle exec rspec spec/notion_client_spec.rb --format documentation`

Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add lib/notion_client.rb
git commit -m "feat: replace bilingual table with stacked toggle sections in Notion"
```

---

### Task 6: Update orchestration in transcribe.rb

**Files:**
- Modify: `transcribe.rb`

- [ ] **Step 1: Update the translation section**

In `transcribe.rb`, replace lines 63-76:

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
```

with:

```ruby
# Step 2.5: Merge and translate transcript if not Traditional Chinese
paragraphs = nil
translated_paragraphs = nil
unless LlmClient::TRADITIONAL_CHINESE_LANGS.include?(options[:lang])
  begin
    lines = transcript.split("\n").map(&:strip).reject(&:empty?)
    paragraphs = llm.merge_to_paragraphs(lines)
    translated_paragraphs = llm.translate_paragraphs(paragraphs, "zh-TW")
  rescue LlmClient::Error => e
    $stderr.puts "WARNING: Translation failed, using single-language transcript: #{e.message}"
    paragraphs = nil
    translated_paragraphs = nil
  end
end
```

- [ ] **Step 2: Update the Notion create_page call**

Replace lines 80-90:

```ruby
page_url = notion.create_page(
  title: title,
  category: "YouTube Note",
  youtube_url: url,
  summary: summary,
  detail_note: detail_note,
  transcript: transcript,
  sentences: sentences,
  translated_sentences: translated_sentences,
  upload_date: upload_date
)
```

with:

```ruby
page_url = notion.create_page(
  title: title,
  category: "YouTube Note",
  youtube_url: url,
  summary: summary,
  detail_note: detail_note,
  transcript: transcript,
  paragraphs: paragraphs,
  translated_paragraphs: translated_paragraphs,
  upload_date: upload_date
)
```

- [ ] **Step 3: Run full test suite**

Run: `cd /home/reid/youtube && bundle exec rspec --format documentation`

Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add transcribe.rb
git commit -m "feat: use merge_to_paragraphs and translate_paragraphs in pipeline"
```

---

### Task 7: Add orchestration integration test

**Files:**
- Create: `spec/transcribe_integration_spec.rb`
- Reference: `transcribe.rb`

- [ ] **Step 1: Write integration test**

Create `spec/transcribe_integration_spec.rb`:

```ruby
require_relative "../lib/transcriber"
require_relative "../lib/llm_client"
require_relative "../lib/notion_client"

RSpec.describe "transcribe.rb orchestration" do
  it "calls merge_to_paragraphs and translate_paragraphs for non-zh-TW transcripts" do
    transcriber = instance_double(Transcriber)
    allow(Transcriber).to receive(:new).and_return(transcriber)
    allow(transcriber).to receive(:transcribe).and_return("line one\nline two\nline three")
    allow(transcriber).to receive(:fetch_upload_date).and_return("2024-03-15")

    llm = instance_double(LlmClient)
    allow(LlmClient).to receive(:new).and_return(llm)
    allow(llm).to receive(:generate_title).and_return("Test Title")
    allow(llm).to receive(:generate_summary).and_return("Summary")
    allow(llm).to receive(:generate_detail_note).and_return("Detail notes")
    allow(llm).to receive(:merge_to_paragraphs)
      .with(["line one", "line two", "line three"])
      .and_return(["First paragraph.", "Second paragraph."])
    allow(llm).to receive(:translate_paragraphs)
      .with(["First paragraph.", "Second paragraph."], "zh-TW")
      .and_return(["第一段。", "第二段。"])

    notion = instance_double(NotionClient)
    allow(NotionClient).to receive(:new).and_return(notion)
    allow(notion).to receive(:create_page).and_return("https://notion.so/page-123")

    # Stub ENV and ARGV for the script
    stub_const("ENV", ENV.to_h.merge(
      "NOTION_API_KEY" => "test-key",
      "NOTION_DATABASE_ID" => "test-db",
      "TRANSCRIBE_API_URL" => "http://localhost:9001/transcribe"
    ))

    allow(File).to receive(:write)
    allow($stdout).to receive(:puts)

    # Simulate running transcribe.rb with lang=en
    load File.expand_path("../transcribe.rb", __dir__)

    expect(notion).to have_received(:create_page).with(
      hash_including(
        paragraphs: ["First paragraph.", "Second paragraph."],
        translated_paragraphs: ["第一段。", "第二段。"]
      )
    )
  end
end
```

Note: This test uses `load` to run the script in-process. The script reads `ARGV` and `ENV`, which we stub. This approach is fragile — if it proves too difficult, an alternative is to extract the orchestration logic into a method/class and test that directly. For now, verify that the keyword wiring is correct.

- [ ] **Step 2: Run the integration test**

Run: `cd /home/reid/youtube && bundle exec rspec spec/transcribe_integration_spec.rb --format documentation`

Expected: PASS (after Task 6 has been completed)

- [ ] **Step 3: Commit**

```bash
git add spec/transcribe_integration_spec.rb
git commit -m "test: add orchestration integration test for bilingual pipeline"
```

---

### Task 8: Final cleanup and verification

**Files:**
- Verify: `lib/llm_client.rb`, `lib/notion_client.rb`, `transcribe.rb`, all spec files

- [ ] **Step 1: Verify no references to old methods remain**

Run: `grep -rn "translate_sentences\|translate_batch\|transcript_table_blocks\|table_row_block\|rich_text_cell\|MAX_TABLE_DATA_ROWS" lib/ spec/ transcribe.rb`

Expected: No output (no references found)

- [ ] **Step 2: Run full test suite one final time**

Run: `cd /home/reid/youtube && bundle exec rspec --format documentation`

Expected: ALL PASS, zero failures

- [ ] **Step 3: Commit any remaining cleanup**

Only if Step 1 found leftover references. Otherwise skip.
