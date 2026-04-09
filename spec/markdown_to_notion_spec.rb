require_relative "../lib/markdown_to_notion"

RSpec.describe MarkdownToNotion do
  describe ".convert" do
    it "converts headings" do
      blocks = MarkdownToNotion.convert("# Title\n## Subtitle\n### Section")
      expect(blocks.length).to eq(3)
      expect(blocks[0]["type"]).to eq("heading_1")
      expect(blocks[0]["heading_1"]["rich_text"][0]["text"]["content"]).to eq("Title")
      expect(blocks[1]["type"]).to eq("heading_2")
      expect(blocks[1]["heading_2"]["rich_text"][0]["text"]["content"]).to eq("Subtitle")
      expect(blocks[2]["type"]).to eq("heading_3")
      expect(blocks[2]["heading_3"]["rich_text"][0]["text"]["content"]).to eq("Section")
    end

    it "converts horizontal rules to dividers" do
      blocks = MarkdownToNotion.convert("Some text\n\n---\n\nMore text")
      expect(blocks[1]["type"]).to eq("divider")
      expect(blocks[1]["divider"]).to eq({})
    end

    it "recognizes all horizontal rule variants" do
      blocks = MarkdownToNotion.convert("---\n\n***\n\n___")
      expect(blocks.length).to eq(3)
      expect(blocks.all? { |b| b["type"] == "divider" }).to be true
    end

    it "converts bulleted lists" do
      blocks = MarkdownToNotion.convert("- Item one\n- Item two\n* Item three")
      expect(blocks.length).to eq(3)
      expect(blocks.all? { |b| b["type"] == "bulleted_list_item" }).to be true
      expect(blocks[0]["bulleted_list_item"]["rich_text"][0]["text"]["content"]).to eq("Item one")
    end

    it "converts numbered lists" do
      blocks = MarkdownToNotion.convert("1. First\n2. Second\n3. Third")
      expect(blocks.length).to eq(3)
      expect(blocks.all? { |b| b["type"] == "numbered_list_item" }).to be true
      expect(blocks[0]["numbered_list_item"]["rich_text"][0]["text"]["content"]).to eq("First")
    end

    it "converts blockquotes" do
      blocks = MarkdownToNotion.convert("> This is a quote")
      expect(blocks[0]["type"]).to eq("quote")
      expect(blocks[0]["quote"]["rich_text"][0]["text"]["content"]).to eq("This is a quote")
    end

    it "converts bold text to annotations" do
      blocks = MarkdownToNotion.convert("This is **bold** text")
      rich_text = blocks[0]["paragraph"]["rich_text"]
      expect(rich_text.length).to eq(3)
      expect(rich_text[0]["text"]["content"]).to eq("This is ")
      expect(rich_text[0]["annotations"]["bold"]).to be false
      expect(rich_text[1]["text"]["content"]).to eq("bold")
      expect(rich_text[1]["annotations"]["bold"]).to be true
      expect(rich_text[2]["text"]["content"]).to eq(" text")
      expect(rich_text[2]["annotations"]["bold"]).to be false
    end

    it "converts italic text to annotations" do
      blocks = MarkdownToNotion.convert("This is *italic* text")
      rich_text = blocks[0]["paragraph"]["rich_text"]
      expect(rich_text[1]["text"]["content"]).to eq("italic")
      expect(rich_text[1]["annotations"]["italic"]).to be true
    end

    it "converts inline code to annotations" do
      blocks = MarkdownToNotion.convert("Use `kubectl` command")
      rich_text = blocks[0]["paragraph"]["rich_text"]
      expect(rich_text[1]["text"]["content"]).to eq("kubectl")
      expect(rich_text[1]["annotations"]["code"]).to be true
    end

    it "handles mixed inline formatting" do
      blocks = MarkdownToNotion.convert("**bold** and *italic* and `code`")
      rich_text = blocks[0]["paragraph"]["rich_text"]
      bold_parts = rich_text.select { |rt| rt["annotations"]["bold"] }
      italic_parts = rich_text.select { |rt| rt["annotations"]["italic"] }
      code_parts = rich_text.select { |rt| rt["annotations"]["code"] }
      expect(bold_parts.length).to eq(1)
      expect(italic_parts.length).to eq(1)
      expect(code_parts.length).to eq(1)
    end

    it "skips empty lines without creating empty blocks" do
      blocks = MarkdownToNotion.convert("Para one\n\n\n\nPara two")
      expect(blocks.length).to eq(2)
      expect(blocks.all? { |b| b["type"] == "paragraph" }).to be true
    end

    it "handles plain paragraphs" do
      blocks = MarkdownToNotion.convert("Just a plain paragraph")
      expect(blocks[0]["type"]).to eq("paragraph")
      expect(blocks[0]["paragraph"]["rich_text"][0]["text"]["content"]).to eq("Just a plain paragraph")
    end

    it "includes object key in every block" do
      blocks = MarkdownToNotion.convert("# Heading\n\nParagraph\n\n- Item")
      blocks.each do |block|
        expect(block["object"]).to eq("block")
      end
    end

    it "handles bold within list items" do
      blocks = MarkdownToNotion.convert("- **Important** item")
      rich_text = blocks[0]["bulleted_list_item"]["rich_text"]
      expect(rich_text[0]["text"]["content"]).to eq("Important")
      expect(rich_text[0]["annotations"]["bold"]).to be true
    end

    it "handles bold within headings" do
      blocks = MarkdownToNotion.convert("## A **bold** heading")
      rich_text = blocks[0]["heading_2"]["rich_text"]
      bold_parts = rich_text.select { |rt| rt["annotations"]["bold"] }
      expect(bold_parts.length).to eq(1)
      expect(bold_parts[0]["text"]["content"]).to eq("bold")
    end

    it "returns empty array for empty input" do
      expect(MarkdownToNotion.convert("")).to eq([])
      expect(MarkdownToNotion.convert("\n\n\n")).to eq([])
    end

    it "splits rich_text objects exceeding 2000 chars" do
      long_text = "a" * 3000
      blocks = MarkdownToNotion.convert(long_text)
      rich_text = blocks[0]["paragraph"]["rich_text"]
      expect(rich_text.length).to eq(2)
      expect(rich_text[0]["text"]["content"].length).to eq(2000)
      expect(rich_text[1]["text"]["content"].length).to eq(1000)
    end

    it "converts a basic markdown table" do
      md = "| Name | Age |\n|------|-----|\n| Alice | 30 |\n| Bob | 25 |"
      blocks = MarkdownToNotion.convert(md)

      expect(blocks.length).to eq(1)
      expect(blocks[0]["type"]).to eq("table")

      table = blocks[0]["table"]
      expect(table["table_width"]).to eq(2)
      expect(table["has_column_header"]).to be true
      expect(table["has_row_header"]).to be false

      rows = table["children"]
      expect(rows.length).to eq(3)  # header + 2 data rows
      expect(rows[0]["table_row"]["cells"][0][0]["text"]["content"]).to eq("Name")
      expect(rows[0]["table_row"]["cells"][1][0]["text"]["content"]).to eq("Age")
      expect(rows[1]["table_row"]["cells"][0][0]["text"]["content"]).to eq("Alice")
      expect(rows[1]["table_row"]["cells"][1][0]["text"]["content"]).to eq("30")
      expect(rows[2]["table_row"]["cells"][0][0]["text"]["content"]).to eq("Bob")
      expect(rows[2]["table_row"]["cells"][1][0]["text"]["content"]).to eq("25")
    end

    it "skips the separator line in tables" do
      md = "| H1 | H2 |\n|:---|---:|\n| A | B |"
      blocks = MarkdownToNotion.convert(md)

      table = blocks[0]["table"]
      rows = table["children"]
      # Should have 2 rows (header + 1 data), NOT 3 (separator excluded)
      expect(rows.length).to eq(2)
    end

    it "handles inline formatting in table cells" do
      md = "| Feature | Status |\n|---------|--------|\n| **Auth** | `done` |"
      blocks = MarkdownToNotion.convert(md)

      data_row = blocks[0]["table"]["children"][1]
      # First cell has bold
      expect(data_row["table_row"]["cells"][0][0]["text"]["content"]).to eq("Auth")
      expect(data_row["table_row"]["cells"][0][0]["annotations"]["bold"]).to be true
      # Second cell has code
      expect(data_row["table_row"]["cells"][1][0]["text"]["content"]).to eq("done")
      expect(data_row["table_row"]["cells"][1][0]["annotations"]["code"]).to be true
    end

    it "handles table surrounded by other content" do
      md = "# Title\n\nSome text\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\nMore text"
      blocks = MarkdownToNotion.convert(md)
      types = blocks.map { |b| b["type"] }

      expect(types).to eq(["heading_1", "paragraph", "table", "paragraph"])
    end

    it "handles 3-column table" do
      md = "| A | B | C |\n|---|---|---|\n| 1 | 2 | 3 |"
      blocks = MarkdownToNotion.convert(md)

      expect(blocks[0]["table"]["table_width"]).to eq(3)
      expect(blocks[0]["table"]["children"][1]["table_row"]["cells"].length).to eq(3)
    end

    it "handles a realistic markdown document" do
      md = <<~MD
        # 影片摘要

        這是一段**重要的**內容。

        ## 重點

        - 第一點
        - **第二點**很重要
        - 使用 `kubectl` 指令

        ---

        > 這是引用文字

        1. 步驟一
        2. 步驟二
      MD

      blocks = MarkdownToNotion.convert(md)
      types = blocks.map { |b| b["type"] }

      expect(types).to eq([
        "heading_1",
        "paragraph",
        "heading_2",
        "bulleted_list_item",
        "bulleted_list_item",
        "bulleted_list_item",
        "divider",
        "quote",
        "numbered_list_item",
        "numbered_list_item"
      ])
    end
  end
end
