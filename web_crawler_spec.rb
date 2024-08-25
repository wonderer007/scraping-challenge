require 'rspec'
require 'webmock/rspec'
require_relative 'web_crawler'

RSpec.describe WebCrawler do
  let(:crawler) { WebCrawler.new(test_env: true) }

  describe '#valid_url?' do
    it 'returns true for valid HTTP URLs' do
      expect(crawler.valid_url?('http://example.com')).to be_truthy
    end

    it 'returns true for valid HTTPS URLs' do
      expect(crawler.valid_url?('https://example.com')).to be_truthy
    end

    it 'returns false for invalid URLs' do
      expect(crawler.valid_url?('not a url')).to be_falsey
    end

    it 'returns false for non-HTTP/HTTPS URLs' do
      expect(crawler.valid_url?('ftp://example.com')).to be_falsey
    end
  end

  describe '#generate_filename' do
    it 'generates correct filename for simple URL' do
      expect(crawler.generate_filename('http://example.com')).to eq('example.com.html')
    end

    it 'generates correct filename for URL with path' do
      expect(crawler.generate_filename('http://example.com/path/to/page')).to eq('example.com-path-to-page.html')
    end

    it 'generates correct filename for URL with query parameters' do
      url = 'http://example.com/page?param=value'
      query = URI(url).query
      query_hash = Digest::MD5.hexdigest(query)[0..7]
      expected_filename = "example.com-page-#{query_hash}.html"
      
      expect(crawler.generate_filename(url)).to eq(expected_filename)
    end
  end

  describe '#crawl_and_save' do
    before do
      WebMock.disable_net_connect!
    end

    after do
      WebMock.allow_net_connect!
    end

    it 'successfully crawls and saves a webpage with correct metadata' do
      html_content = <<-HTML
        <html>
          <body>
            <a href='#'>Link 1</a>
            <a href='#'>Link 2</a>
            <img src='image1.jpg'>
            <img src='image2.jpg'>
            <img src='image3.jpg'>
            Hello World
          </body>
        </html>
      HTML

      stub_request(:get, 'http://example.com').
        to_return(status: 200, body: html_content)

      result = crawler.crawl_and_save('http://example.com')

      expect(result[:success]).to be_truthy
      expect(result[:filename]).to eq('example.com.html')
      expect(File.exist?('example.com.html')).to be_truthy
      expect(result[:links_count]).to eq(2)
      expect(result[:images_count]).to eq(3)
    end

    it 'updates last_modified when recrawling an existing file' do
      stub_request(:get, 'http://example.com').
        to_return(status: 200, body: '<html><body>Hello World</body></html>')

      first_crawl = crawler.crawl_and_save('http://example.com')

      allow(File).to receive(:exist?).with('example.com.html').and_return(true)
      allow(File).to receive(:mtime).with('example.com.html').and_return(Time.utc(2023, 7, 15, 13, 0, 0))

      second_crawl = crawler.crawl_and_save('http://example.com')
      expect(second_crawl[:last_modified]).to eq(Time.utc(2023, 7, 15, 13, 0, 0))
    end

    it 'handles unsuccessful redirect due to max_redirects limit' do
      stub_request(:get, 'http://example.com')
        .to_return(status: 302, headers: { 'Location' => 'http://example2.com' })
      stub_request(:get, 'http://example2.com')
        .to_return(status: 302, headers: { 'Location' => 'http://example3.com' })
      stub_request(:get, 'http://example3.com')
        .to_return(status: 302, headers: { 'Location' => 'http://example4.com' })
      stub_request(:get, 'http://example4.com')
        .to_return(status: 302, headers: { 'Location' => 'http://example5.com' })
      stub_request(:get, 'http://example5.com')
        .to_return(status: 302, headers: { 'Location' => 'http://example6.com' })

      result = crawler.crawl_and_save('http://example.com')

      expect(result[:success]).to be_falsey
      expect(result[:error]).to include('Too many redirects')
    end    

    it 'handles redirects with metadata' do
      html_content = <<-HTML
        <html>
          <body>
            <a href='#'>Link 1</a>
            <img src='image1.jpg'>
            Redirected Content
          </body>
        </html>
      HTML

      stub_request(:get, 'http://example.com').
        to_return(status: 302, headers: { 'Location' => 'http://www.example.com' })
      stub_request(:get, 'http://www.example.com').
        to_return(status: 200, body: html_content)

      result = crawler.crawl_and_save('http://example.com')
      expect(result[:success]).to be_truthy
      expect(result[:filename]).to eq('www.example.com.html')
      expect(result[:links_count]).to eq(1)
      expect(result[:images_count]).to eq(1)
    end

    it 'handles errors' do
      stub_request(:get, 'http://example.com').to_return(status: 404)

      result = crawler.crawl_and_save('http://example.com')
      expect(result[:success]).to be_falsey
      expect(result[:error]).to include('Failed to crawl')
    end
  end

  describe '#crawl_urls' do
    before do
      WebMock.disable_net_connect!
    end

    after do
      WebMock.allow_net_connect!
    end

    it 'processes multiple URLs' do
      stub_request(:get, 'http://example.com').
        to_return(status: 200, body: '<html><body>Example</body></html>')
      stub_request(:get, 'http://test.com').
        to_return(status: 200, body: '<html><body>Test</body></html>')

      urls = ['http://example.com', 'http://test.com', 'invalid_url']
      results = crawler.crawl_urls(urls)

      expect(results.keys).to contain_exactly('http://example.com', 'http://test.com', 'invalid_url')
      expect(results['http://example.com'][:success]).to be_truthy
      expect(results['http://test.com'][:success]).to be_truthy
      expect(results['invalid_url'][:success]).to be_falsey
    end

    it 'does not sleep in test environment' do
      stub_request(:get, 'http://example1.com').
        to_return(status: 200, body: '<html><body>Example 1</body></html>')
      stub_request(:get, 'http://example2.com').
        to_return(status: 200, body: '<html><body>Example 2</body></html>')

      urls = ['http://example1.com', 'http://example2.com']
      
      expect(crawler).not_to receive(:sleep)
      crawler.crawl_urls(urls)
    end    
  end
end
