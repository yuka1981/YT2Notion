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
      expect(call_count).to eq(2)
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
end
