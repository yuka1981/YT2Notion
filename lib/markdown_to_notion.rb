# frozen_string_literal: true

require "strscan"

class MarkdownToNotion
  MAX_RICH_TEXT_LENGTH = 2000

  def self.convert(markdown)
    lines = markdown.lines.map(&:chomp)
    blocks = []
    table_lines = []

    lines.each do |line|
      if table_line?(line)
        table_lines << line
        next
      end

      # Non-table line: flush any accumulated table
      unless table_lines.empty?
        blocks << build_table_block(table_lines)
        table_lines = []
      end

      next if line.strip.empty?

      block = parse_line(line)
      blocks << block if block
    end

    # Flush remaining table lines at end of input
    blocks << build_table_block(table_lines) unless table_lines.empty?

    blocks
  end

  class << self
    private

    def table_line?(line)
      line.strip.match?(/^\|.+\|$/)
    end

    def separator_line?(line)
      cells = line.strip.gsub(/^\||\|$/, "").split("|")
      cells.all? { |cell| cell.strip.match?(/^[-:\s]+$/) }
    end

    def build_table_block(lines)
      rows = []
      lines.each do |line|
        next if separator_line?(line)

        cells = line.strip.gsub(/^\||\|$/, "").split("|").map(&:strip)
        row_cells = cells.map { |cell_text| parse_inline(cell_text) }
        rows << {
          "object" => "block",
          "type" => "table_row",
          "table_row" => { "cells" => row_cells }
        }
      end

      table_width = rows.first ? rows.first["table_row"]["cells"].length : 0

      {
        "object" => "block",
        "type" => "table",
        "table" => {
          "table_width" => table_width,
          "has_column_header" => true,
          "has_row_header" => false,
          "children" => rows
        }
      }
    end

    def parse_line(line)
      case line
      when /\A(---|\*\*\*|___)\s*\z/
        divider_block
      when /\A###\s+(.*)/
        heading_block(3, Regexp.last_match(1))
      when /\A##\s+(.*)/
        heading_block(2, Regexp.last_match(1))
      when /\A#\s+(.*)/
        heading_block(1, Regexp.last_match(1))
      when /\A[-*]\s+(.*)/
        bulleted_list_block(Regexp.last_match(1))
      when /\A\d+\.\s+(.*)/
        numbered_list_block(Regexp.last_match(1))
      when /\A>\s+(.*)/
        quote_block(Regexp.last_match(1))
      else
        paragraph_block(line)
      end
    end

    def heading_block(level, text)
      type = "heading_#{level}"
      {
        "object" => "block",
        "type" => type,
        type => { "rich_text" => parse_inline(text) }
      }
    end

    def paragraph_block(text)
      {
        "object" => "block",
        "type" => "paragraph",
        "paragraph" => { "rich_text" => parse_inline(text) }
      }
    end

    def bulleted_list_block(text)
      {
        "object" => "block",
        "type" => "bulleted_list_item",
        "bulleted_list_item" => { "rich_text" => parse_inline(text) }
      }
    end

    def numbered_list_block(text)
      {
        "object" => "block",
        "type" => "numbered_list_item",
        "numbered_list_item" => { "rich_text" => parse_inline(text) }
      }
    end

    def quote_block(text)
      {
        "object" => "block",
        "type" => "quote",
        "quote" => { "rich_text" => parse_inline(text) }
      }
    end

    def divider_block
      {
        "object" => "block",
        "type" => "divider",
        "divider" => {}
      }
    end

    def parse_inline(text)
      tokens = tokenize_inline(text)
      rich_text_objects = tokens.flat_map { |token| split_long_text(token) }
      rich_text_objects
    end

    # Scans text and produces rich_text tokens with annotations.
    # Handles **bold**, *italic*, and `code` markers.
    def tokenize_inline(text)
      tokens = []
      scanner = StringScanner.new(text)

      current = ""
      bold = false
      italic = false
      code = false

      while !scanner.eos?
        if scanner.scan(/`([^`]+)`/)
          # Flush current plain text
          tokens << rich_text_token(current, bold, italic, false) unless current.empty?
          current = ""
          # Add code token
          tokens << rich_text_token(scanner[1], bold, italic, true)
        elsif scanner.scan(/\*\*([^*]+)\*\*/)
          tokens << rich_text_token(current, bold, italic, false) unless current.empty?
          current = ""
          tokens << rich_text_token(scanner[1], true, italic, false)
        elsif scanner.scan(/\*([^*]+)\*/)
          tokens << rich_text_token(current, bold, italic, false) unless current.empty?
          current = ""
          tokens << rich_text_token(scanner[1], bold, true, false)
        else
          current += scanner.getch
        end
      end

      tokens << rich_text_token(current, bold, italic, code) unless current.empty?
      tokens
    end

    def rich_text_token(content, bold, italic, code)
      {
        "type" => "text",
        "text" => { "content" => content },
        "annotations" => {
          "bold" => bold,
          "italic" => italic,
          "code" => code
        }
      }
    end

    def split_long_text(token)
      content = token["text"]["content"]
      return [token] if content.length <= MAX_RICH_TEXT_LENGTH

      chunks = content.scan(/.{1,#{MAX_RICH_TEXT_LENGTH}}/m)
      chunks.map do |chunk|
        {
          "type" => "text",
          "text" => { "content" => chunk },
          "annotations" => token["annotations"].dup
        }
      end
    end
  end
end
