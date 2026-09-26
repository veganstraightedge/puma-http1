# frozen_string_literal: true

require_relative "http/version"

module Puma
  # An HTTP parser for Puma, written in Ruby. Use it with Puma's
  # `http_parser` option:
  #
  #   require "puma/http"
  #   http_parser Puma::HTTP::Parser
  module HTTP
  end
end
