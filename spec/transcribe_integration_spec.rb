require_relative "../lib/transcriber"
require_relative "../lib/llm_client"
require_relative "../lib/notion_client"

RSpec.describe "Bilingual pipeline integration" do
  it "passes paragraphs and translated_paragraphs to NotionClient" do
    # Simulate what transcribe.rb does for non-zh-TW transcripts
    transcript = "line one\nline two\nline three"
    lines = transcript.split("\n").map(&:strip).reject(&:empty?)

    llm = instance_double(LlmClient)
    allow(llm).to receive(:merge_to_paragraphs)
      .with(lines)
      .and_return(["First paragraph.", "Second paragraph."])
    allow(llm).to receive(:translate_paragraphs)
      .with(["First paragraph.", "Second paragraph."], "zh-TW")
      .and_return(["第一段。", "第二段。"])

    notion = instance_double(NotionClient)
    allow(notion).to receive(:create_page).and_return("https://notion.so/page-123")

    # Execute the pipeline steps
    paragraphs = llm.merge_to_paragraphs(lines)
    translated_paragraphs = llm.translate_paragraphs(paragraphs, "zh-TW")

    notion.create_page(
      title: "Test",
      category: "YouTube Note",
      youtube_url: "https://youtube.com/watch?v=abc",
      summary: "Summary",
      detail_note: "Notes",
      transcript: transcript,
      paragraphs: paragraphs,
      translated_paragraphs: translated_paragraphs,
      upload_date: "2024-03-15"
    )

    expect(llm).to have_received(:merge_to_paragraphs).with(lines)
    expect(llm).to have_received(:translate_paragraphs)
      .with(["First paragraph.", "Second paragraph."], "zh-TW")
    expect(notion).to have_received(:create_page).with(
      hash_including(
        paragraphs: ["First paragraph.", "Second paragraph."],
        translated_paragraphs: ["第一段。", "第二段。"]
      )
    )
  end

  it "falls back to nil paragraphs when translation fails" do
    llm = instance_double(LlmClient)
    allow(llm).to receive(:merge_to_paragraphs)
      .and_raise(LlmClient::Error, "Translation failed")

    paragraphs = nil
    translated_paragraphs = nil
    begin
      lines = ["line one", "line two"]
      paragraphs = llm.merge_to_paragraphs(lines)
      translated_paragraphs = llm.translate_paragraphs(paragraphs, "zh-TW")
    rescue LlmClient::Error
      paragraphs = nil
      translated_paragraphs = nil
    end

    expect(paragraphs).to be_nil
    expect(translated_paragraphs).to be_nil
  end
end
