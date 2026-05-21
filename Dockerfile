FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libpq-dev nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

COPY . .

RUN mkdir -p tmp

EXPOSE 8080

CMD ["sh", "-lc", "node render-email-config.js && bundle exec puma -C config/puma.rb"]