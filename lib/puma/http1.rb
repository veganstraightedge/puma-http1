# frozen_string_literal: true

require_relative "http1/version"
require_relative "http1/parser"

module Puma
  # An HTTP/1.x parser for Puma, written in Ruby. Use it with Puma's
  # `http_parser` option:
  #
  #   require "puma/http1"
  #   http_parser Puma::HTTP1::Parser
  #
  # It's named HTTP1, not HTTP, because Puma::Const::HTTP exists, and Puma's
  # code refers to it without the Const:: prefix. A Puma::HTTP module would be
  # found first and break Puma.
  module HTTP1
  end
end
