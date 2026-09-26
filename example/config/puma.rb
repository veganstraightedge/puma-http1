# frozen_string_literal: true

require "puma/http1"

http_parser Puma::HTTP1::Parser

port ENV.fetch("PORT", 9292)
threads 1, 4
