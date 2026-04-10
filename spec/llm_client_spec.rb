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
        "根據以下逐字稿，用繁體中文生成一個簡短的標題，不要使用任何 markdown 格式",
        "some transcript"
      )
      expect(result).to eq("Karpenter 介紹")
    end

    it "uses English title prompt" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("Intro to Karpenter")

      result = client.generate_title("some transcript", "en")
      expect(client).to have_received(:generate).with(
        "Generate a concise title for the following transcript, no markdown formatting",
        "some transcript"
      )
      expect(result).to eq("Intro to Karpenter")
    end

    it "uses generic prompt for other languages" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("タイトル")

      result = client.generate_title("some transcript", "ja")
      expect(client).to have_received(:generate).with(
        "Generate a concise title for the following transcript in ja, no markdown formatting",
        "some transcript"
      )
      expect(result).to eq("タイトル")
    end

    it "strips bold markdown from title" do
      client = LlmClient.new("claude")
      allow(client).to receive(:generate).and_return("**高情商說話的秘訣**")

      result = client.generate_title("some transcript", "zh-TW")
      expect(result).to eq("高情商說話的秘訣")
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

  describe "::TRADITIONAL_CHINESE_LANGS" do
    it "includes zh-TW, zh-Hant, zh-HK" do
      expect(LlmClient::TRADITIONAL_CHINESE_LANGS).to contain_exactly("zh-TW", "zh-Hant", "zh-HK")
    end
  end

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
end
