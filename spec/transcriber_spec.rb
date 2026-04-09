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
