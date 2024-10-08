# Web Crawler
Web Crawler to crawl list of given urls and fetch the content of the page

## How to run
```
./fetch https://www.google.com https://www.atlassian.com/software/jira
```

## Run Tests
Make sure to `bundle install` before running tests

```
rspec web_crawler_spec.rb
```

## Features

- Fetches and saves web pages from provided URLs
- Metadata collection (enabled by default)

## TODO

- Normalize URLs to avoid crawling the same page multiple times i.e. https://www.google.com and www.google.com are same pages
- Respect robots.txt files
- Improve file naming to avoid collisions

## Note

Metadata collection is enabled by default without an explicit --metadata flag.