# YouTube Transcription + Notion Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Ruby CLI tool that transcribes YouTube videos, generates title/summary/detail notes via LLM CLI tools, saves locally, and publishes to Notion.

**Architecture:** Three focused Ruby classes (Transcriber, LlmClient, NotionClient) orchestrated by a CLI entry point. Each class has a single responsibility with a clean interface. TDD with RSpec and WebMock for HTTP stubbing.

**Tech Stack:** Ruby, RSpec, WebMock, dotenv, net/http, Notion API v2022-06-28, CLI tools (claude/codex/gemini)

---

### File Structure

```
Gemfile                    # Dependencies
.rspec                     # RSpec config
transcribe.rb              # CLI entry point
lib/
  transcriber.rb           # Transcription API client
  llm_client.rb            # LLM CLI tool wrapper
  notion_client.rb         # Notion API client
spec/
  spec_helper.rb           # RSpec + WebMock config
  transcriber_spec.rb      # Transcriber tests
  llm_client_spec.rb       # LlmClient tests
  notion_client_spec.rb    # NotionClient tests
```

---

### Task 1: Project scaffolding

**Files:**
- Create: `Gemfile`
- Create: `.rspec`
- Create: `spec/spec_helper.rb`

- [ ] **Step 1: Create the Gemfile**

```ruby
# Gemfile
source "https://rubygems.org"

gem "dotenv"

group :test do
  gem "rspec"
  gem "webmock"
end
```

- [ ] **Step 2: Create .rspec config**

```
--format documentation
--color
--require spec_helper
```

- [ ] **Step 3: Create spec/spec_helper.rb**

```ruby
# spec/spec_helper.rb
require "webmock/rspec"
require "json"

WebMock.disable_net_connect!

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
end
```

- [ ] **Step 4: Install dependencies**

Run: `cd /home/reid/youtube && bundle install`
Expected: Gems install successfully, `Gemfile.lock` created.

- [ ] **Step 5: Verify RSpec runs**

Run: `cd /home/reid/youtube && bundle exec rspec`
Expected: `0 examples, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock .rspec spec/spec_helper.rb
git commit -m "chore: scaffold Ruby project with RSpec and WebMock"
```

---

### Task 2: Transcriber

**Files:**
- Create: `lib/transcriber.rb`
- Create: `spec/transcriber_spec.rb`

- [ ] **Step 1: Write failing tests for Transcriber**

```ruby
# spec/transcriber_spec.rb
require_relative "../lib/transcriber"

RSpec.describe Transcriber do
  let(:api_url) { "http://localhost:9001/transcribe" }
  let(:transcriber) { Transcriber.new(api_url) }

  describe "#transcribe" do
    it "returns transcript text on success" do
      stub_request(:post, api_url)
        .with(
          body: { url: "https://youtube.com/watch?v=abc", lang: "zh" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(
          status: 200,
          body: { text: "hello world transcript" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = transcriber.transcribe("https://youtube.com/watch?v=abc", "zh")
      expect(result).to eq("hello world transcript")
    end

    it "raises an error when API returns non-200" do
      stub_request(:post, api_url)
        .to_return(status: 500, body: "Internal Server Error")

      expect {
        transcriber.transcribe("https://youtube.com/watch?v=abc", "zh")
      }.to raise_error(Transcriber::Error, /Transcription API failed.*500/)
    end

    it "raises an error when response has no text field" do
      stub_request(:post, api_url)
        .to_return(
          status: 200,
          body: { detail: "unsupported format" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect {
        transcriber.transcribe("https://youtube.com/watch?v=abc", "zh")
      }.to raise_error(Transcriber::Error, /No transcript text/)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/reid/youtube && bundle exec rspec spec/transcriber_spec.rb`
Expected: FAIL — `cannot load such file -- lib/transcriber`

- [ ] **Step 3: Write the Transcriber implementation**

```ruby
# lib/transcriber.rb
require "net/http"
require "json"
require "uri"

class Transcriber
  class Error < StandardError; end

  def initialize(api_url)
    @api_url = api_url
  end

  def transcribe(url, lang)
    uri = URI(@api_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 1800

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request.body = { url: url, lang: lang }.to_json

    response = http.request(request)

    unless response.code.to_i == 200
      raise Error, "Transcription API failed with status #{response.code}: #{response.body}"
    end

    data = JSON.parse(response.body)
    text = data["text"]

    if text.nil? || text.empty?
      detail = data["detail"] || "unknown error"
      raise Error, "No transcript text in response: #{detail}"
    end

    text
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/reid/youtube && bundle exec rspec spec/transcriber_spec.rb`
Expected: `3 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/transcriber.rb spec/transcriber_spec.rb
git commit -m "feat: add Transcriber class with API client and tests"
```

---

### Task 3: LlmClient

**Files:**
- Create: `lib/llm_client.rb`
- Create: `spec/llm_client_spec.rb`

- [ ] **Step 1: Write failing tests for LlmClient**

```ruby
# spec/llm_client_spec.rb
require_relative "../lib/llm_client"

RSpec.describe LlmClient do
  describe "#generate" do
    it "calls claude with -p flag" do
      client = LlmClient.new("claude")
      allow(client).to receive(:`).and_return("summary output\n")
      allow($?).to receive(:success?).and_return(true)

      result = client.generate("Summarize this", "some text")
      expect(result).to eq("summary output")
    end

    it "calls codex with exec subcommand" do
      client = LlmClient.new("codex")
      allow(client).to receive(:`).and_return("codex output\n")
      allow($?).to receive(:success?).and_return(true)

      result = client.generate("Summarize this", "some text")
      expect(result).to eq("codex output")
    end

    it "calls gemini with -p flag" do
      client = LlmClient.new("gemini")
      allow(client).to receive(:`).and_return("gemini output\n")
      allow($?).to receive(:success?).and_return(true)

      result = client.generate("Summarize this", "some text")
      expect(result).to eq("gemini output")
    end

    it "raises error for unknown CLI tool" do
      expect {
        LlmClient.new("unknown")
      }.to raise_error(LlmClient::Error, /Unknown CLI tool/)
    end

    it "raises error when command returns empty output" do
      client = LlmClient.new("claude")
      allow(client).to receive(:`).and_return("")
      allow($?).to receive(:success?).and_return(true)

      expect {
        client.generate("Summarize this", "some text")
      }.to raise_error(LlmClient::Error, /empty output/)
    end
  end

  describe "#generate_title" do
    it "uses zh-TW title prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Karpenter 介紹")

      result = client.generate_title("some transcript", "zh-TW")
      expect(client).to have_received(:generate).with(
        "根據以下逐字稿，用繁體中文生成一個簡短的標題",
        "some transcript"
      )
      expect(result).to eq("Karpenter 介紹")
    end

    it "uses English title prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Intro to Karpenter")

      result = client.generate_title("some transcript", "en")
      expect(client).to have_received(:generate).with(
        "Generate a concise title for the following transcript",
        "some transcript"
      )
      expect(result).to eq("Intro to Karpenter")
    end
  end

  describe "#generate_summary" do
    it "uses zh-TW summary prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("摘要內容")

      client.generate_summary("transcript text", "zh-TW")
      expect(client).to have_received(:generate).with(
        "用繁體中文摘要以下影片逐字稿",
        "transcript text"
      )
    end

    it "uses English summary prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Summary content")

      client.generate_summary("transcript text", "en")
      expect(client).to have_received(:generate).with(
        "Summarize the following video transcript in English",
        "transcript text"
      )
    end
  end

  describe "#generate_detail_note" do
    it "uses zh-TW detail note prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("結構化筆記")

      client.generate_detail_note("transcript text", "zh-TW")
      expect(client).to have_received(:generate).with(
        "用繁體中文將以下影片逐字稿整理成結構化筆記，包含標題、重點摘要、分段說明與要點列表",
        "transcript text"
      )
    end

    it "uses English detail note prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Structured notes")

      client.generate_detail_note("transcript text", "en")
      expect(client).to have_received(:generate).with(
        "Organize the following video transcript into structured notes with headings, key takeaways, sections, and bullet points in English",
        "transcript text"
      )
    end

    it "uses generic prompt for other languages" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Notes in Japanese")

      client.generate_detail_note("transcript text", "ja")
      expect(client).to have_received(:generate).with(
        "Organize the following video transcript into structured notes with headings, key takeaways, sections, and bullet points in ja",
        "transcript text"
      )
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/reid/youtube && bundle exec rspec spec/llm_client_spec.rb`
Expected: FAIL — `cannot load such file -- lib/llm_client`

- [ ] **Step 3: Write the LlmClient implementation**

```ruby
# lib/llm_client.rb
require "open3"
require "shellwords"

class LlmClient
  class Error < StandardError; end

  SUPPORTED_TOOLS = %w[claude codex gemini].freeze

  def initialize(cli_tool)
    unless SUPPORTED_TOOLS.include?(cli_tool)
      raise Error, "Unknown CLI tool '#{cli_tool}'. Use: #{SUPPORTED_TOOLS.join(', ')}"
    end
    @cli_tool = cli_tool
  end

  def generate(prompt, input_text)
    cmd = build_command(prompt)
    output, status = Open3.capture2(cmd, stdin_data: input_text)

    unless status.success?
      raise Error, "CLI tool '#{@cli_tool}' failed with exit code #{status.exitstatus}"
    end

    result = output.strip
    if result.empty?
      raise Error, "CLI tool '#{@cli_tool}' returned empty output"
    end

    result
  end

  def generate_title(transcript, lang)
    prompt = case lang
             when "zh-TW" then "根據以下逐字稿，用繁體中文生成一個簡短的標題"
             when "en" then "Generate a concise title for the following transcript"
             else "Generate a concise title for the following transcript in #{lang}"
             end
    generate(prompt, transcript)
  end

  def generate_summary(transcript, lang)
    prompt = case lang
             when "zh-TW" then "用繁體中文摘要以下影片逐字稿"
             when "en" then "Summarize the following video transcript in English"
             else "Summarize the following video transcript in #{lang}"
             end
    generate(prompt, transcript)
  end

  def generate_detail_note(transcript, lang)
    prompt = case lang
             when "zh-TW" then "用繁體中文將以下影片逐字稿整理成結構化筆記，包含標題、重點摘要、分段說明與要點列表"
             when "en" then "Organize the following video transcript into structured notes with headings, key takeaways, sections, and bullet points in English"
             else "Organize the following video transcript into structured notes with headings, key takeaways, sections, and bullet points in #{lang}"
             end
    generate(prompt, transcript)
  end

  private

  def build_command(prompt)
    escaped_prompt = Shellwords.escape(prompt)
    case @cli_tool
    when "claude" then "claude -p #{escaped_prompt}"
    when "codex" then "codex exec #{escaped_prompt}"
    when "gemini" then "gemini -p #{escaped_prompt}"
    end
  end
end
```

- [ ] **Step 4: Update tests to use Open3 stubbing instead of backticks**

Since the implementation uses `Open3.capture2` instead of backticks, update the test stubs:

```ruby
# spec/llm_client_spec.rb
require_relative "../lib/llm_client"

RSpec.describe LlmClient do
  describe "#generate" do
    it "calls claude with -p flag" do
      client = LlmClient.new("claude")
      allow(Open3).to receive(:capture2)
        .and_return(["summary output\n", double(success?: true)])

      result = client.generate("Summarize this", "some text")
      expect(result).to eq("summary output")
      expect(Open3).to have_received(:capture2).with(
        "claude -p Summarize\\ this",
        stdin_data: "some text"
      )
    end

    it "calls codex with exec subcommand" do
      client = LlmClient.new("codex")
      allow(Open3).to receive(:capture2)
        .and_return(["codex output\n", double(success?: true)])

      result = client.generate("Summarize this", "some text")
      expect(result).to eq("codex output")
      expect(Open3).to have_received(:capture2).with(
        "codex exec Summarize\\ this",
        stdin_data: "some text"
      )
    end

    it "calls gemini with -p flag" do
      client = LlmClient.new("gemini")
      allow(Open3).to receive(:capture2)
        .and_return(["gemini output\n", double(success?: true)])

      result = client.generate("Summarize this", "some text")
      expect(result).to eq("gemini output")
      expect(Open3).to have_received(:capture2).with(
        "gemini -p Summarize\\ this",
        stdin_data: "some text"
      )
    end

    it "raises error for unknown CLI tool" do
      expect {
        LlmClient.new("unknown")
      }.to raise_error(LlmClient::Error, /Unknown CLI tool/)
    end

    it "raises error when command returns empty output" do
      client = LlmClient.new("claude")
      allow(Open3).to receive(:capture2)
        .and_return(["", double(success?: true)])

      expect {
        client.generate("Summarize this", "some text")
      }.to raise_error(LlmClient::Error, /empty output/)
    end

    it "raises error when command fails" do
      client = LlmClient.new("claude")
      allow(Open3).to receive(:capture2)
        .and_return(["", double(success?: false, exitstatus: 1)])

      expect {
        client.generate("Summarize this", "some text")
      }.to raise_error(LlmClient::Error, /failed with exit code 1/)
    end
  end

  describe "#generate_title" do
    it "uses zh-TW title prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Karpenter 介紹")

      result = client.generate_title("some transcript", "zh-TW")
      expect(client).to have_received(:generate).with(
        "根據以下逐字稿，用繁體中文生成一個簡短的標題",
        "some transcript"
      )
      expect(result).to eq("Karpenter 介紹")
    end

    it "uses English title prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Intro to Karpenter")

      result = client.generate_title("some transcript", "en")
      expect(client).to have_received(:generate).with(
        "Generate a concise title for the following transcript",
        "some transcript"
      )
      expect(result).to eq("Intro to Karpenter")
    end

    it "uses generic prompt for other languages" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("タイトル")

      result = client.generate_title("some transcript", "ja")
      expect(client).to have_received(:generate).with(
        "Generate a concise title for the following transcript in ja",
        "some transcript"
      )
      expect(result).to eq("タイトル")
    end
  end

  describe "#generate_summary" do
    it "uses zh-TW summary prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("摘要內容")

      client.generate_summary("transcript text", "zh-TW")
      expect(client).to have_received(:generate).with(
        "用繁體中文摘要以下影片逐字稿",
        "transcript text"
      )
    end

    it "uses English summary prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Summary content")

      client.generate_summary("transcript text", "en")
      expect(client).to have_received(:generate).with(
        "Summarize the following video transcript in English",
        "transcript text"
      )
    end
  end

  describe "#generate_detail_note" do
    it "uses zh-TW detail note prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("結構化筆記")

      client.generate_detail_note("transcript text", "zh-TW")
      expect(client).to have_received(:generate).with(
        "用繁體中文將以下影片逐字稿整理成結構化筆記，包含標題、重點摘要、分段說明與要點列表",
        "transcript text"
      )
    end

    it "uses English detail note prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Structured notes")

      client.generate_detail_note("transcript text", "en")
      expect(client).to have_received(:generate).with(
        "Organize the following video transcript into structured notes with headings, key takeaways, sections, and bullet points in English",
        "transcript text"
      )
    end

    it "uses generic prompt for other languages" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Notes in Japanese")

      client.generate_detail_note("transcript text", "ja")
      expect(client).to have_received(:generate).with(
        "Organize the following video transcript into structured notes with headings, key takeaways, sections, and bullet points in ja",
        "transcript text"
      )
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /home/reid/youtube && bundle exec rspec spec/llm_client_spec.rb`
Expected: `13 examples, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add lib/llm_client.rb spec/llm_client_spec.rb
git commit -m "feat: add LlmClient with CLI tool dispatch and prompt generation"
```

---

### Task 4: NotionClient

**Files:**
- Create: `lib/notion_client.rb`
- Create: `spec/notion_client_spec.rb`

- [ ] **Step 1: Write failing tests for NotionClient**

```ruby
# spec/notion_client_spec.rb
require_relative "../lib/notion_client"

RSpec.describe NotionClient do
  let(:api_key) { "ntn_test_key" }
  let(:database_id) { "db-123" }
  let(:client) { NotionClient.new(api_key, database_id) }
  let(:notion_api) { "https://api.notion.com/v1/pages" }

  describe "#create_page" do
    it "creates a Notion page and returns the URL" do
      stub_request(:post, notion_api)
        .with(
          headers: {
            "Authorization" => "Bearer ntn_test_key",
            "Content-Type" => "application/json",
            "Notion-Version" => "2022-06-28"
          }
        )
        .to_return(
          status: 200,
          body: { object: "page", id: "page-abc-123", url: "https://www.notion.so/page-abc-123" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      url = client.create_page(
        title: "Test Title",
        category: "YouTube Note",
        summary: "A short summary",
        detail_note: "Detailed notes here",
        transcript: "Full transcript text"
      )

      expect(url).to eq("https://www.notion.so/page-abc-123")
    end

    it "sends correct page properties" do
      stub_request(:post, notion_api)
        .to_return(
          status: 200,
          body: { object: "page", id: "page-1", url: "https://www.notion.so/page-1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      client.create_page(
        title: "My Title",
        category: "YouTube Note",
        summary: "Summary",
        detail_note: "Notes",
        transcript: "Transcript"
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        props = body["properties"]

        props["Doc name"]["title"][0]["text"]["content"] == "My Title" &&
          props["Category"]["multi_select"][0]["name"] == "YouTube Note" &&
          body["parent"]["database_id"] == "db-123"
      }
    end

    it "sends correct children blocks structure" do
      stub_request(:post, notion_api)
        .to_return(
          status: 200,
          body: { object: "page", id: "page-1", url: "https://www.notion.so/page-1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      client.create_page(
        title: "Title",
        category: "YouTube Note",
        summary: "My summary",
        detail_note: "My notes",
        transcript: "My transcript"
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        children = body["children"]

        children[0]["type"] == "heading_2" &&
          children[0]["heading_2"]["rich_text"][0]["text"]["content"] == "Summary" &&
          children[1]["type"] == "paragraph" &&
          children[1]["paragraph"]["rich_text"][0]["text"]["content"] == "My summary" &&
          children[2]["type"] == "divider" &&
          children[3]["type"] == "heading_2" &&
          children[3]["heading_2"]["rich_text"][0]["text"]["content"] == "Detail Note" &&
          children[4]["type"] == "paragraph" &&
          children[4]["paragraph"]["rich_text"][0]["text"]["content"] == "My notes" &&
          children[5]["type"] == "divider" &&
          children[6]["type"] == "heading_2" &&
          children[6]["heading_2"]["rich_text"][0]["text"]["content"] == "Full Transcript" &&
          children[7]["type"] == "paragraph" &&
          children[7]["paragraph"]["rich_text"][0]["text"]["content"] == "My transcript"
      }
    end

    it "splits text longer than 2000 chars into multiple paragraph blocks" do
      stub_request(:post, notion_api)
        .to_return(
          status: 200,
          body: { object: "page", id: "page-1", url: "https://www.notion.so/page-1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      long_text = "a" * 4500

      client.create_page(
        title: "Title",
        category: "YouTube Note",
        summary: "Short",
        detail_note: "Short",
        transcript: long_text
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        children = body["children"]
        # heading_2 "Full Transcript" is at index 6
        # paragraphs for transcript start at index 7
        transcript_paragraphs = children[7..]
        transcript_paragraphs.length == 3 &&
          transcript_paragraphs.all? { |b| b["type"] == "paragraph" } &&
          transcript_paragraphs[0]["paragraph"]["rich_text"][0]["text"]["content"].length == 2000 &&
          transcript_paragraphs[1]["paragraph"]["rich_text"][0]["text"]["content"].length == 2000 &&
          transcript_paragraphs[2]["paragraph"]["rich_text"][0]["text"]["content"].length == 500
      }
    end

    it "raises error when Notion API returns non-200" do
      stub_request(:post, notion_api)
        .to_return(
          status: 400,
          body: { object: "error", message: "Invalid request" }.to_json
        )

      expect {
        client.create_page(
          title: "Title",
          category: "YouTube Note",
          summary: "Summary",
          detail_note: "Notes",
          transcript: "Transcript"
        )
      }.to raise_error(NotionClient::Error, /Notion API failed.*400/)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/reid/youtube && bundle exec rspec spec/notion_client_spec.rb`
Expected: FAIL — `cannot load such file -- lib/notion_client`

- [ ] **Step 3: Write the NotionClient implementation**

```ruby
# lib/notion_client.rb
require "net/http"
require "json"
require "uri"

class NotionClient
  class Error < StandardError; end

  NOTION_API_URL = "https://api.notion.com/v1/pages"
  NOTION_BLOCKS_URL = "https://api.notion.com/v1/blocks"
  NOTION_VERSION = "2022-06-28"
  MAX_TEXT_LENGTH = 2000
  MAX_CHILDREN_PER_REQUEST = 100

  def initialize(api_key, database_id)
    @api_key = api_key
    @database_id = database_id
  end

  def create_page(title:, category:, summary:, detail_note:, transcript:)
    children = build_children(summary, detail_note, transcript)

    # Split into initial batch and overflow
    initial_children = children.first(MAX_CHILDREN_PER_REQUEST)
    overflow_children = children[MAX_CHILDREN_PER_REQUEST..]

    body = {
      parent: { database_id: @database_id },
      properties: build_properties(title, category),
      children: initial_children
    }

    response = post_request(NOTION_API_URL, body)
    data = JSON.parse(response.body)

    unless response.code.to_i == 200
      message = data["message"] || response.body
      raise Error, "Notion API failed with status #{response.code}: #{message}"
    end

    # Append overflow blocks if any
    if overflow_children && !overflow_children.empty?
      page_id = data["id"]
      append_children(page_id, overflow_children)
    end

    data["url"]
  end

  private

  def build_properties(title, category)
    {
      "Doc name" => {
        "title" => [{ "text" => { "content" => title } }]
      },
      "Category" => {
        "multi_select" => [{ "name" => category }]
      }
    }
  end

  def build_children(summary, detail_note, transcript)
    children = []
    children << heading_block("Summary")
    children.concat(text_blocks(summary))
    children << divider_block
    children << heading_block("Detail Note")
    children.concat(text_blocks(detail_note))
    children << divider_block
    children << heading_block("Full Transcript")
    children.concat(text_blocks(transcript))
    children
  end

  def heading_block(text)
    {
      "object" => "block",
      "type" => "heading_2",
      "heading_2" => {
        "rich_text" => [{ "type" => "text", "text" => { "content" => text } }]
      }
    }
  end

  def divider_block
    { "object" => "block", "type" => "divider", "divider" => {} }
  end

  def text_blocks(text)
    chunks = split_text(text)
    chunks.map do |chunk|
      {
        "object" => "block",
        "type" => "paragraph",
        "paragraph" => {
          "rich_text" => [{ "type" => "text", "text" => { "content" => chunk } }]
        }
      }
    end
  end

  def split_text(text)
    return [text] if text.length <= MAX_TEXT_LENGTH

    chunks = []
    remaining = text
    while remaining.length > MAX_TEXT_LENGTH
      chunks << remaining[0...MAX_TEXT_LENGTH]
      remaining = remaining[MAX_TEXT_LENGTH..]
    end
    chunks << remaining unless remaining.empty?
    chunks
  end

  def append_children(block_id, children)
    children.each_slice(MAX_CHILDREN_PER_REQUEST) do |batch|
      url = "#{NOTION_BLOCKS_URL}/#{block_id}/children"
      response = post_request(url, { children: batch })
      unless response.code.to_i == 200
        raise Error, "Notion API failed appending blocks: #{response.code}"
      end
    end
  end

  def post_request(url, body)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request["Notion-Version"] = NOTION_VERSION
    request.body = body.to_json

    http.request(request)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/reid/youtube && bundle exec rspec spec/notion_client_spec.rb`
Expected: `5 examples, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/notion_client.rb spec/notion_client_spec.rb
git commit -m "feat: add NotionClient with page creation and text chunking"
```

---

### Task 5: CLI entry point

**Files:**
- Create: `transcribe.rb`

- [ ] **Step 1: Write the CLI entry point**

```ruby
#!/usr/bin/env ruby
# transcribe.rb

require "optparse"
require "dotenv/load"
require_relative "lib/transcriber"
require_relative "lib/llm_client"
require_relative "lib/notion_client"

options = {
  lang: "zh",
  summary_lang: "zh-TW",
  cli: "claude"
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby transcribe.rb YOUTUBE_URL [options]"

  opts.on("--lang LANG", "Transcription language (default: zh)") { |v| options[:lang] = v }
  opts.on("--summary-lang LANG", "Summary language (default: zh-TW)") { |v| options[:summary_lang] = v }
  opts.on("--cli TOOL", "CLI tool: claude, codex, gemini (default: claude)") { |v| options[:cli] = v }
  opts.on("-h", "--help", "Show help") do
    puts opts
    exit
  end
end

parser.parse!

url = ARGV[0]
if url.nil? || url.empty?
  puts parser.banner
  exit 1
end

# Validate required env vars
missing = %w[NOTION_API_KEY NOTION_DATABASE_ID TRANSCRIBE_API_URL].select { |key| ENV[key].nil? || ENV[key].empty? }
unless missing.empty?
  $stderr.puts "ERROR: Missing required environment variables: #{missing.join(', ')}"
  exit 1
end

timestamp = Time.now.to_i
transcript_file = "./transcript_#{timestamp}.txt"
summary_file = "./summary_#{timestamp}.txt"

begin
  # Step 1: Transcribe
  transcriber = Transcriber.new(ENV["TRANSCRIBE_API_URL"])
  transcript = transcriber.transcribe(url, options[:lang])
  File.write(transcript_file, transcript)
  puts transcript_file

  # Step 2: LLM calls
  llm = LlmClient.new(options[:cli])
  title = llm.generate_title(transcript, options[:summary_lang])
  summary = llm.generate_summary(transcript, options[:summary_lang])
  detail_note = llm.generate_detail_note(transcript, options[:summary_lang])
  File.write(summary_file, summary)
  puts summary_file

  # Step 3: Upload to Notion
  notion = NotionClient.new(ENV["NOTION_API_KEY"], ENV["NOTION_DATABASE_ID"])
  page_url = notion.create_page(
    title: title,
    category: "YouTube Note",
    summary: summary,
    detail_note: detail_note,
    transcript: transcript
  )
  puts page_url

rescue Transcriber::Error => e
  $stderr.puts "ERROR: #{e.message}"
  exit 1

rescue LlmClient::Error => e
  $stderr.puts "ERROR: #{e.message}"
  exit 1

rescue NotionClient::Error => e
  $stderr.puts "WARNING: Failed to upload to Notion: #{e.message}"
  # Don't exit — local files are preserved
end
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x /home/reid/youtube/transcribe.rb`

- [ ] **Step 3: Verify the script parses arguments correctly**

Run: `cd /home/reid/youtube && ruby transcribe.rb --help`
Expected: Usage banner with all options listed.

Run: `cd /home/reid/youtube && ruby transcribe.rb`
Expected: Usage banner, exit code 1.

- [ ] **Step 4: Update .env with required variables**

Add `NOTION_DATABASE_ID` and `TRANSCRIBE_API_URL` to `.env`:

```
NOTION_API_KEY=ntn_o20420694523l5Z4JUF8f7kTjyaOvd6SE9Py3ql2lcUbRB
NOTION_DATABASE_ID=26b079b781cc80cd961bf2f601652cc8
TRANSCRIBE_API_URL=http://10.106.37.191:9001/transcribe
```

- [ ] **Step 5: Commit**

```bash
git add transcribe.rb .env
git commit -m "feat: add CLI entry point with argument parsing and pipeline orchestration"
```

---

### Task 6: Run all tests and verify

**Files:**
- None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `cd /home/reid/youtube && bundle exec rspec`
Expected: All tests pass (21 examples, 0 failures).

- [ ] **Step 2: Verify no syntax errors in all Ruby files**

Run: `cd /home/reid/youtube && ruby -c transcribe.rb && ruby -c lib/transcriber.rb && ruby -c lib/llm_client.rb && ruby -c lib/notion_client.rb`
Expected: `Syntax OK` for each file.

- [ ] **Step 3: Commit (if any fixes were needed)**

```bash
git add -A
git commit -m "fix: address issues found during full test run"
```
