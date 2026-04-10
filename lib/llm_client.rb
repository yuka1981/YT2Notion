require "open3"
require "shellwords"

class LlmClient
  class Error < StandardError; end

  SUPPORTED_TOOLS = %w[claude codex gemini].freeze
  TRADITIONAL_CHINESE_LANGS = %w[zh-TW zh-Hant zh-HK].freeze
  TRANSLATION_BATCH_SIZE = 50

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
             when "zh-TW" then "根據以下逐字稿，用繁體中文生成一個簡短的標題，不要使用任何 markdown 格式"
             when "en" then "Generate a concise title for the following transcript, no markdown formatting"
             else "Generate a concise title for the following transcript in #{lang}, no markdown formatting"
             end
    result = generate(prompt, transcript)
    result.gsub(/\*+/, "").strip
  end

  def generate_summary(transcript, lang)
    prompt = case lang
             when "zh-TW" then "用繁體中文摘要以下影片逐字稿"
             when "en" then "Summarize the following video transcript in English"
             else "Summarize the following video transcript in #{lang}"
             end
    generate(prompt, transcript)
  end

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
