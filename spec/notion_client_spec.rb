require_relative "../lib/notion_client"

RSpec.describe NotionClient do
  let(:api_key) { "ntn_test_key" }
  let(:database_id) { "db-123" }
  let(:client) { NotionClient.new(api_key, database_id) }
  let(:notion_api) { "https://api.notion.com/v1/pages" }

  before do
    stub_request(:post, notion_api)
      .to_return(
        status: 200,
        body: { object: "page", id: "page-abc-123", url: "https://www.notion.so/page-abc-123" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  let(:youtube_url) { "https://www.youtube.com/watch?v=abc123" }

  describe "#create_page" do
    it "creates a Notion page and returns the URL" do
      url = client.create_page(
        title: "Test Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "A short summary",
        detail_note: "Detailed notes here",
        transcript: "Full transcript text"
      )

      expect(url).to eq("https://www.notion.so/page-abc-123")
    end

    it "sends correct page properties" do
      client.create_page(
        title: "My Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
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

    it "embeds YouTube video as first block" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "Transcript"
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        children = body["children"]
        video = children[0]

        video["type"] == "video" &&
          video["video"]["type"] == "external" &&
          video["video"]["external"]["url"] == "https://www.youtube.com/watch?v=abc123"
      }
    end

    it "sends correct top-level block structure" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "My summary",
        detail_note: "My notes",
        transcript: "My transcript"
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        children = body["children"]

        # Video + Summary heading + paragraph(s) from markdown + divider + Detail Note heading + paragraph(s) from markdown + divider + toggle heading
        children[0]["type"] == "video" &&
          children[1]["type"] == "heading_2" &&
          children[1]["heading_2"]["rich_text"][0]["text"]["content"] == "Summary" &&
          children[-2]["type"] == "divider" &&
          children[-1]["type"] == "heading_2" &&
          children[-1]["heading_2"]["rich_text"][0]["text"]["content"] == "Full Transcript" &&
          children[-1]["heading_2"]["is_toggleable"] == true &&
          children.count { |c| c["type"] == "divider" } == 2
      }
    end

    it "makes Full Transcript a collapsible toggle heading with transcript as children" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "The full transcript content"
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        children = body["children"]
        toggle = children.last

        toggle["type"] == "heading_2" &&
          toggle["heading_2"]["is_toggleable"] == true &&
          toggle["heading_2"]["rich_text"][0]["text"]["content"] == "Full Transcript" &&
          toggle["heading_2"]["children"].length == 1 &&
          toggle["heading_2"]["children"][0]["type"] == "paragraph" &&
          toggle["heading_2"]["children"][0]["paragraph"]["rich_text"][0]["text"]["content"] == "The full transcript content"
      }
    end

    it "converts markdown in summary and detail_note to Notion blocks" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "## Key Points\n\n- Point one\n- **Point two**",
        detail_note: "Notes",
        transcript: "Transcript"
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        children = body["children"]

        # After video (index 0) and "Summary" heading (index 1), markdown blocks follow
        # ## Key Points -> heading_2, - Point one -> bulleted_list_item, - **Point two** -> bulleted_list_item
        children[2]["type"] == "heading_2" &&
          children[2]["heading_2"]["rich_text"][0]["text"]["content"] == "Key Points" &&
          children[3]["type"] == "bulleted_list_item" &&
          children[4]["type"] == "bulleted_list_item"
      }
    end

    it "splits long transcript into multiple paragraph children in toggle" do
      long_text = "a" * 4500

      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Short",
        detail_note: "Short",
        transcript: long_text
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        children = body["children"]
        toggle = children.last
        transcript_children = toggle["heading_2"]["children"]

        transcript_children.length == 3 &&
          transcript_children.all? { |b| b["type"] == "paragraph" } &&
          transcript_children[0]["paragraph"]["rich_text"][0]["text"]["content"].length == 2000 &&
          transcript_children[1]["paragraph"]["rich_text"][0]["text"]["content"].length == 2000 &&
          transcript_children[2]["paragraph"]["rich_text"][0]["text"]["content"].length == 500
      }
    end

    it "builds a dual-language table when sentences and translated_sentences are provided" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "full text",
        sentences: ["hello", "world"],
        translated_sentences: ["你好", "世界"]
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        toggle = body["children"].last

        toggle["heading_2"]["is_toggleable"] == true &&
          toggle["heading_2"]["children"][0]["type"] == "table" &&
          toggle["heading_2"]["children"][0]["table"]["table_width"] == 2 &&
          toggle["heading_2"]["children"][0]["table"]["has_column_header"] == true
      }
    end

    it "includes header row and data rows in dual-language table" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "full text",
        sentences: ["hello"],
        translated_sentences: ["你好"]
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        toggle = body["children"].last
        table = toggle["heading_2"]["children"][0]
        rows = table["table"]["children"]

        rows.length == 2 &&
          rows[0]["table_row"]["cells"][0][0]["text"]["content"] == "Original" &&
          rows[0]["table_row"]["cells"][1][0]["text"]["content"] == "繁體中文" &&
          rows[1]["table_row"]["cells"][0][0]["text"]["content"] == "hello" &&
          rows[1]["table_row"]["cells"][1][0]["text"]["content"] == "你好"
      }
    end

    it "chunks dual-language table at 99 data rows" do
      sentences = (1..150).map { |i| "line #{i}" }
      translated = (1..150).map { |i| "翻譯 #{i}" }

      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "full text",
        sentences: sentences,
        translated_sentences: translated
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        toggle = body["children"].last
        tables = toggle["heading_2"]["children"]

        tables.length == 2 &&
          tables[0]["type"] == "table" &&
          tables[0]["table"]["children"].length == 100 &&
          tables[1]["type"] == "table" &&
          tables[1]["table"]["children"].length == 52
      }
    end

    it "falls back to paragraph blocks when no translation provided" do
      client.create_page(
        title: "Title",
        category: "YouTube Note",
        youtube_url: youtube_url,
        summary: "Summary",
        detail_note: "Notes",
        transcript: "The full transcript content"
      )

      expect(WebMock).to have_requested(:post, notion_api).with { |req|
        body = JSON.parse(req.body)
        toggle = body["children"].last

        toggle["heading_2"]["children"][0]["type"] == "paragraph"
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
          youtube_url: youtube_url,
          summary: "Summary",
          detail_note: "Notes",
          transcript: "Transcript"
        )
      }.to raise_error(NotionClient::Error, /Notion API failed.*400/)
    end
  end
end
