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
  upload_date = transcriber.fetch_upload_date(url)
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
    youtube_url: url,
    summary: summary,
    detail_note: detail_note,
    transcript: transcript,
    upload_date: upload_date
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
