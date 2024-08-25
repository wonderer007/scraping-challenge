#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'digest'
require 'nokogiri'
require 'time'

class WebCrawler
  def initialize(test_env: false)
    @test_env = test_env
  end

  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def generate_filename(url)
    uri = URI(url)
    path = uri.path.delete_suffix('/')
    
    filename = uri.host
    filename += path.tr('/', '-') unless path.empty?
    
    unless uri.query.nil? || uri.query.empty?
      query_hash = Digest::MD5.hexdigest(uri.query)[0..7]
      filename += "-#{query_hash}"
    end
    
    "#{filename}.html"
  end

  def extract_metadata(body)
    doc = Nokogiri::HTML(body)
    {
      links_count: doc.css('a').size,
      images_count: doc.css('img').size
    }
  end

  def get_last_modified(filename)
    File.exist?(filename) ? File.mtime(filename).utc : Time.now.utc
  end

  def format_time(time)
    time.strftime('%a %b %d %Y %H:%M UTC')
  end

  def crawl_and_save(url, max_redirects = 3)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    
    response = http.get(uri.request_uri)
    
    handle_response(response, url, max_redirects)
  rescue StandardError => e
    handle_error(nil, url, e)
  end

  def handle_response(response, url, max_redirects)
    case response
    when Net::HTTPSuccess then handle_success(response, url)
    when Net::HTTPRedirection then handle_redirect(response, url, max_redirects)
    else handle_error(response, url)
    end
  rescue StandardError => e
    handle_error(response, url, e)
  end

  def handle_success(response, url)
    filename = generate_filename(url)
    File.write(filename, response.body)
    
    metadata = extract_metadata(response.body)
    last_modified = get_last_modified(filename)
    
    print_metadata(url, filename, last_modified, metadata)
    
    {
      success: true,
      filename: filename,
      last_modified: last_modified,
      links_count: metadata[:links_count],
      images_count: metadata[:images_count]
    }
  end

  def handle_redirect(response, url, max_redirects)
    if max_redirects.positive?
      new_url = response['location']
      puts "Redirected to #{new_url}"
      crawl_and_save(new_url, max_redirects - 1)
    else
      handle_error(response, url, StandardError.new('Too many redirects'))
    end
  end

  def handle_error(response, url, error = nil)
    error_message = if error
                      "Error crawling #{url}: #{error.message}"
                    elsif response
                      "Failed to crawl #{url}: #{response.code} #{response.message}"
                    else
                      "Unknown error crawling #{url}"
                    end
    
    puts error_message
    { success: false, error: error_message }
  end

  def print_metadata(url, filename, last_modified, metadata)
    puts "site: #{url}"
    puts "  Last crawl time: #{format_time(last_modified)}"
    puts "  Number of links: #{metadata[:links_count]}"
    puts "  Number of images: #{metadata[:images_count]}"
  end

  def crawl_urls(urls)
    urls.each_with_object({}) do |url, results|
      results[url] = if valid_url?(url)
                       result = crawl_and_save(url)
                       sleep 1 unless @test_env
                       result
                     else
                       puts "Invalid URL: #{url}"
                       { success: false, error: 'Invalid URL' }
                     end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  crawler = WebCrawler.new
  if ARGV.empty?
    puts "Usage: #{$PROGRAM_NAME} URL1 URL2 ..."
    exit 1
  end
  crawler.crawl_urls(ARGV)
end
