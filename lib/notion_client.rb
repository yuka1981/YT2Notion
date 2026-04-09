require "net/http"
require "json"
require "uri"
require_relative "markdown_to_notion"

class NotionClient
  class Error < StandardError; end

  NOTION_API_URL = "https://api.notion.com/v1/pages"
  NOTION_BLOCKS_URL = "https://api.notion.com/v1/blocks"
  NOTION_VERSION = "2022-06-28"
  MAX_TEXT_LENGTH = 2000
  MAX_CHILDREN_PER_REQUEST = 100

  def initialize(api_key, database_id)
    @api_key = api_key
    @database_id = database_id
  end

  def create_page(title:, category:, youtube_url:, summary:, detail_note:, transcript:)
    children = build_children(youtube_url, summary, detail_note, transcript)

    initial_children = children.first(MAX_CHILDREN_PER_REQUEST)
    overflow_children = children[MAX_CHILDREN_PER_REQUEST..]

    body = {
      parent: { database_id: @database_id },
      properties: build_properties(title, category),
      children: initial_children
    }

    response = post_request(NOTION_API_URL, body)
    data = JSON.parse(response.body)

    unless response.code.to_i == 200
      message = data["message"] || response.body
      raise Error, "Notion API failed with status #{response.code}: #{message}"
    end

    if overflow_children && !overflow_children.empty?
      page_id = data["id"]
      append_children(page_id, overflow_children)
    end

    data["url"]
  end

  private

  def build_properties(title, category)
    {
      "Doc name" => {
        "title" => [{ "text" => { "content" => title } }]
      },
      "Category" => {
        "multi_select" => [{ "name" => category }]
      }
    }
  end

  def build_children(youtube_url, summary, detail_note, transcript)
    children = []
    children << video_block(youtube_url)
    children << heading_block("Summary")
    children.concat(MarkdownToNotion.convert(summary))
    children << divider_block
    children << heading_block("Detail Note")
    children.concat(MarkdownToNotion.convert(detail_note))
    children << divider_block
    children << toggle_heading_block("Full Transcript", text_blocks(transcript))
    children
  end

  def heading_block(text)
    {
      "object" => "block",
      "type" => "heading_2",
      "heading_2" => {
        "rich_text" => [{ "type" => "text", "text" => { "content" => text } }]
      }
    }
  end

  def toggle_heading_block(text, children_blocks)
    {
      "object" => "block",
      "type" => "heading_2",
      "heading_2" => {
        "rich_text" => [{ "type" => "text", "text" => { "content" => text } }],
        "is_toggleable" => true,
        "children" => children_blocks
      }
    }
  end

  def video_block(url)
    {
      "object" => "block",
      "type" => "video",
      "video" => {
        "type" => "external",
        "external" => { "url" => url }
      }
    }
  end

  def divider_block
    { "object" => "block", "type" => "divider", "divider" => {} }
  end

  def text_blocks(text)
    chunks = split_text(text)
    chunks.map do |chunk|
      {
        "object" => "block",
        "type" => "paragraph",
        "paragraph" => {
          "rich_text" => [{ "type" => "text", "text" => { "content" => chunk } }]
        }
      }
    end
  end

  def split_text(text)
    return [text] if text.length <= MAX_TEXT_LENGTH

    chunks = []
    remaining = text
    while remaining.length > MAX_TEXT_LENGTH
      chunks << remaining[0...MAX_TEXT_LENGTH]
      remaining = remaining[MAX_TEXT_LENGTH..]
    end
    chunks << remaining unless remaining.empty?
    chunks
  end

  def append_children(block_id, children)
    children.each_slice(MAX_CHILDREN_PER_REQUEST) do |batch|
      url = "#{NOTION_BLOCKS_URL}/#{block_id}/children"
      response = patch_request(url, { children: batch })
      unless response.code.to_i == 200
        raise Error, "Notion API failed appending blocks: #{response.code}"
      end
    end
  end

  def patch_request(url, body)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Patch.new(uri.path)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request["Notion-Version"] = NOTION_VERSION
    request.body = body.to_json

    http.request(request)
  end

  def post_request(url, body)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request["Notion-Version"] = NOTION_VERSION
    request.body = body.to_json

    http.request(request)
  end
end
