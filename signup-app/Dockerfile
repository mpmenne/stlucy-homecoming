FROM ruby:3.3-slim AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV RAILS_ENV=production \
    BUNDLE_WITHOUT="development test"

COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf /usr/local/bundle/cache

COPY . .

FROM ruby:3.3-slim

WORKDIR /app
ENV RAILS_ENV=production \
    BUNDLE_WITHOUT="development test"

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

RUN useradd --create-home appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
