# frozen_string_literal: true

require_relative "helper"
require "puma"

# Runs the same requests through Puma's own parser, from its puma_http11
# extension, and through Puma::HTTP1::Parser, and expects the same results.
class TestParserCompatibility < Minitest::Test
  REQUESTS = [
    "GET / HTTP/1.1\r\n\r\n",
    "GET /?a=1 HTTP/1.1\r\nHost: example.com\r\n\r\n",
    "POST /orders HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
    "GET http://h:3000/p?q=1 HTTP/1.1\r\n\r\n",
    "OPTIONS * HTTP/1.1\r\n\r\n",
    "GET /a?b#frag HTTP/1.1\r\n\r\n",
    "GET /# HTTP/1.1\r\n\r\n",
    "GET :foo HTTP/1.1\r\n\r\n",
    "GET //a//b?c=/? HTTP/1.1\r\n\r\n",
    "GET / HTTP/10.02\r\n\r\n",
    "GET /caf\xC3\xA9?x=\xFF HTTP/1.1\r\n\r\n".b,
    "GET / HTTP/1.1\r\nX:\r\nX-Spaces:   \r\nX-Tab:\tv\r\n\r\n",
    "GET / HTTP/1.1\r\nX-A: 1\r\nx-a: 2\r\n\r\n",
    "GET / HTTP/1.1\r\nX_Forwarded_For: 1\r\nX-Forwarded-For: 2\r\n\r\n",
    "GET / HTTP/1.1\r\nCookie: a=1; b=2\r\nUser-Agent: curl/8.7.1\r\n\r\nGET / HTTP/1.1\r\n\r\n",
    "get / HTTP/1.1\r\n\r\n",
    "GET abc HTTP/1.1\r\n\r\n",
    "GET / HTTP/1.\r\n\r\n",
    "GET / HTTP/1.1\n\n",
    "GET / HTTP/1.1\r\nX :1\r\n\r\n",
    "GET / HTTP/1.1\r\nDummy: x\nDummy2: y\r\n\r\n",
    "#{"A" * 21} / HTTP/1.1\r\n\r\n",
    "GET / HTTP/1.1\r\n#{"a" * 257}: val\r\n\r\n",
    "\x16\x03\x01\x02\x00\x01\x00\x01".b
  ].freeze

  def setup
    skip "Puma's puma_http11 extension is not loaded" unless Puma.const_defined?(:HttpParser, false)
  end

  # Parses request, split into pieces of chunk_size bytes, the way Puma feeds
  # a parser as data arrives, and returns everything a caller could observe.
  def outcome(parser_class, request, chunk_size:)
    parser = parser_class.new
    env = {}
    buffer = +""
    nread = 0
    error = nil

    request.b.each_char.each_slice(chunk_size) do |chunk|
      buffer << chunk.join
      begin
        # Puma passes the same buffer to every call. The C parser relies on
        # that, because it upcases header names inside the buffer, and a name
        # can span two calls.
        nread = parser.execute(env, buffer, nread)
      rescue Puma::HttpParserError => e
        error = e.message
        break
      end
    end

    { body: parser.body, env:, error:, error?: parser.error?, finished?: parser.finished?, nread: }
  end

  def assert_same_outcome(chunk_size: nil)
    REQUESTS.each do |request|
      size = chunk_size || request.bytesize
      expected = outcome(Puma::HttpParser, request, chunk_size: size)
      actual = outcome(Puma::HTTP1::Parser, request, chunk_size: size)

      assert_equal expected, actual, "#{request.inspect} in #{size} byte pieces"
    end
  end

  def test_matches_for_whole_requests
    assert_same_outcome
  end

  def test_matches_for_requests_in_7_byte_pieces
    assert_same_outcome(chunk_size: 7)
  end

  def test_matches_for_requests_in_1_byte_pieces
    assert_same_outcome(chunk_size: 1)
  end
end
