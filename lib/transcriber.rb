require "net/http"
require "json"
require "uri"
require "open3"
require "tmpdir"

class Transcriber
  class Error < StandardError; end

  def initialize(api_url)
    @api_url = api_url
  end

  def transcribe(url, lang)
    text = fetch_cc(url, lang)
    if text
      $stderr.puts "Using CC subtitle for transcription"
      return text
    end

    $stderr.puts "No CC found, falling back to transcription API"
    transcribe_via_api(url, lang)
  end

  def fetch_upload_date(youtube_url)
    output, status = Open3.capture2("yt-dlp", "--print", "%(upload_date>%Y-%m-%d)s", "--skip-download", youtube_url)
    return output.strip if status.success? && output.strip =~ /\A\d{4}-\d{2}-\d{2}\z/

    nil
  end

  private

  def fetch_cc(url, lang)
    Dir.mktmpdir do |dir|
      output_template = File.join(dir, "sub")
      sub_lang = [lang, "#{lang}-*"].join(",")

      Open3.capture2(
        "yt-dlp",
        "--write-sub", "--write-auto-sub",
        "--sub-lang", sub_lang,
        "--skip-download", "--sub-format", "vtt",
        "-o", output_template,
        url
      )

      sub_file = Dir.glob(File.join(dir, "*.{vtt,srt}")).first
      return nil unless sub_file

      parse_vtt(File.read(sub_file))
    end
  end

  def parse_vtt(content)
    lines = content.lines.map(&:strip)
    text_lines = []
    seen = {}

    lines.each do |line|
      next if line.empty?
      next if line == "WEBVTT"
      next if line =~ /^Kind:|^Language:/
      next if line =~ /^\d{2}:\d{2}/ # timestamp lines
      next if line =~ /^NOTE/
      next if line =~ /^\d+$/ # SRT sequence numbers

      clean = line.gsub(/<[^>]+>/, "").strip
      next if clean.empty?
      next if seen[clean]

      seen[clean] = true
      text_lines << clean
    end

    result = text_lines.join("\n")
    result.empty? ? nil : result
  end

  def transcribe_via_api(url, lang)
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
