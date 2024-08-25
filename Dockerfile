FROM ruby:3.0

WORKDIR /usr/src/app
COPY . .
RUN gem install bundler:1.17.2
RUN bundle install
EXPOSE 80
RUN echo '#!/bin/bash\nruby /usr/src/app/web_crawler.rb "$@"' > /usr/local/bin/web_crawler && \
  chmod +x /usr/local/bin/web_crawler

ENTRYPOINT ["web_crawler"]