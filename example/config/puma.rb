# frozen_string_literal: true

require "puma/http"

http_parser Puma::HTTP::Parser

port ENV.fetch("PORT", 9292)
threads 1, 4
