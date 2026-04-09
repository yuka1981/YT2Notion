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
