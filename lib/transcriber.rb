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

  def fetch_upload_date(youtube_url)
    uri = URI(youtube_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    return nil unless response.code.to_i == 200

    match = response.body.match(/"uploadDate":"([^"]+)"/)
    return nil unless match

    match[1][0, 10] # Extract YYYY-MM-DD from ISO 8601
  end
end
