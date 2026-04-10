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
  MAX_BLOCKS_PER_REQUEST = 1000

  def initialize(api_key, database_id)
    @api_key = api_key
    @database_id = database_id
  end

  def create_page(title:, category:, youtube_url:, summary:, detail_note:, transcript:, upload_date: nil)
    children, toggle_overflow = build_children(youtube_url, summary, detail_note, transcript)

    initial_children = children.first(MAX_CHILDREN_PER_REQUEST)
    overflow_children = children[MAX_CHILDREN_PER_REQUEST..]

    body = {
      parent: { database_id: @database_id },
      properties: build_properties(title, category, upload_date),
      children: initial_children
    }

    response = post_request(NOTION_API_URL, body)
    data = JSON.parse(response.body)

    unless response.code.to_i == 200
      message = data["message"] || response.body
      raise Error, "Notion API failed with status #{response.code}: #{message}"
    end

    page_id = data["id"]

    if overflow_children && !overflow_children.empty?
      append_children(page_id, overflow_children)
    end

    if toggle_overflow && !toggle_overflow.empty?
      toggle_id = find_toggle_block_id(page_id)
      append_children(toggle_id, toggle_overflow)
    end

    data["url"]
  end

  private

  def build_properties(title, category, upload_date)
    props = {
      "Doc name" => {
        "title" => [{ "text" => { "content" => title } }]
      },
      "Category" => {
        "multi_select" => [{ "name" => category }]
      }
    }

    if upload_date
      props["Upload Date"] = {
        "date" => { "start" => upload_date }
      }
    end

    props
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

    transcript_blocks = text_blocks(transcript)

    # Reserve budget for the toggle heading itself (+1) and other page children
    used_blocks = count_blocks(children) + 1
    budget = MAX_BLOCKS_PER_REQUEST - used_blocks
    initial_transcript, overflow_transcript = split_blocks_by_budget(transcript_blocks, budget)

    if initial_transcript.empty?
      children << toggle_heading_block_empty("Full Transcript")
    else
      children << toggle_heading_block("Full Transcript", initial_transcript)
    end

    [children, overflow_transcript]
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

  def toggle_heading_block_empty(text)
    {
      "object" => "block",
      "type" => "heading_2",
      "heading_2" => {
        "rich_text" => [{ "type" => "text", "text" => { "content" => text } }],
        "is_toggleable" => true
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

  def count_blocks(blocks)
    blocks.sum do |block|
      count = 1
      %w[heading_1 heading_2 heading_3 table].each do |type|
        nested = block.dig(type, "children")
        if nested
          count += count_blocks(nested)
          break
        end
      end
      count
    end
  end

  def split_blocks_by_budget(blocks, budget)
    initial = []
    overflow = []
    used = 0

    blocks.each do |block|
      bc = count_blocks([block])
      if used + bc <= budget
        initial << block
        used += bc
      else
        overflow << block
      end
    end

    [initial, overflow]
  end

  def append_children(block_id, children)
    batch = []
    batch_count = 0

    children.each do |child|
      child_count = count_blocks([child])

      if !batch.empty? && (batch.size >= MAX_CHILDREN_PER_REQUEST || batch_count + child_count > MAX_BLOCKS_PER_REQUEST)
        flush_append(block_id, batch)
        batch = []
        batch_count = 0
      end

      batch << child
      batch_count += child_count
    end

    flush_append(block_id, batch) unless batch.empty?
  end

  def flush_append(block_id, batch)
    url = "#{NOTION_BLOCKS_URL}/#{block_id}/children"
    response = patch_request(url, { children: batch })
    unless response.code.to_i == 200
      data = JSON.parse(response.body)
      message = data["message"] || response.body
      raise Error, "Notion API failed appending blocks: #{message}"
    end
  end

  def find_toggle_block_id(page_id)
    cursor = nil
    last_toggle_id = nil

    loop do
      url = "#{NOTION_BLOCKS_URL}/#{page_id}/children?page_size=100"
      url += "&start_cursor=#{cursor}" if cursor
      response = get_request(url)
      data = JSON.parse(response.body)

      data["results"].each do |block|
        if block["type"] == "heading_2" && block.dig("heading_2", "is_toggleable")
          last_toggle_id = block["id"]
        end
      end

      break unless data["has_more"]
      cursor = data["next_cursor"]
    end

    raise Error, "Could not find toggle block for appending transcript" unless last_toggle_id
    last_toggle_id
  end

  def get_request(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Notion-Version"] = NOTION_VERSION

    http.request(request)
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
