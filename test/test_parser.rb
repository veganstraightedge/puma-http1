# frozen_string_literal: true

require_relative "helper"
require "digest"

class TestParser < Minitest::Test
  INVALID_FORMAT_MESSAGE = "Invalid HTTP format, parsing fails. " \
                           "Are you trying to open an SSL connection to a non-SSL Puma?"

  def setup
    @parser = Puma::HTTP1::Parser.new
    @env = {}
  end

  # Readable or binary garbage of a random length, from Puma's test suite.
  def random_data(min, max, readable: true)
    count = min + ((rand(max) + 1) * 10).to_i
    data = "#{count}/"

    if readable
      data << (Digest(:SHA1).hexdigest(rand(count * 100).to_s) * (count / 40))
    else
      binary = Digest(:SHA1).digest(rand(count * 100).to_s) * (count / 20)
      # Guarantee there is an invalid byte at the end of the string
      binary.setbyte(binary.bytesize - 1, 0x1)
      data << binary
    end

    data
  end

  # execute

  def test_parses_a_simple_http11_request
    request = "GET /?a=1 HTTP/1.1\r\n\r\n"
    nread = @parser.execute(@env, request, 0)

    assert_equal request.bytesize, nread
    assert @parser.finished?
    refute @parser.error?
    assert_equal nread, @parser.nread

    expected = {
      "QUERY_STRING" => "a=1",
      "REQUEST_METHOD" => "GET",
      "REQUEST_PATH" => "/",
      "REQUEST_URI" => "/?a=1",
      "SERVER_PROTOCOL" => "HTTP/1.1"
    }
    assert_equal expected, @env
  end

  def test_parses_a_simple_http10_request
    @parser.execute(@env, "GET / HTTP/1.0\r\n\r\n", 0)

    assert @parser.finished?
    expected = {
      "REQUEST_METHOD" => "GET",
      "REQUEST_PATH" => "/",
      "REQUEST_URI" => "/",
      "SERVER_PROTOCOL" => "HTTP/1.0"
    }
    assert_equal expected, @env
  end

  def test_keeps_escapes_and_a_bare_percent_in_the_query
    @parser.execute(@env, "GET /admin/users?search=%27%%27 HTTP/1.1\r\n\r\n", 0)

    assert_equal "/admin/users?search=%27%%27", @env["REQUEST_URI"]
    assert_equal "search=%27%%27", @env["QUERY_STRING"]
  end

  def test_leaves_the_path_and_query_of_an_absolute_uri_to_puma
    @parser.execute(@env, "GET http://192.168.1.96:3000/api/v1/matches/test?1=1 HTTP/1.1\r\n\r\n", 0)

    assert_equal "http://192.168.1.96:3000/api/v1/matches/test?1=1", @env["REQUEST_URI"]
    refute @env.key?("REQUEST_PATH")
    refute @env.key?("QUERY_STRING")
    refute @env.key?("FRAGMENT")
  end

  def test_parses_star_as_the_request_uri
    @parser.execute(@env, "OPTIONS * HTTP/1.1\r\n\r\n", 0)

    assert_equal "OPTIONS", @env["REQUEST_METHOD"]
    assert_equal "*", @env["REQUEST_URI"]
    refute @env.key?("REQUEST_PATH")
  end

  def test_separates_the_fragment_from_the_request_uri
    @parser.execute(@env, "GET /forums/1/topics/2375?page=1#posts-17408 HTTP/1.1\r\n\r\n", 0)

    assert_equal "/forums/1/topics/2375?page=1", @env["REQUEST_URI"]
    assert_equal "posts-17408", @env["FRAGMENT"]
  end

  def test_allows_a_semicolon_in_the_path
    @parser.execute(@env, "GET /forums/1/path;stillpath/2375?page=1 HTTP/1.1\r\n\r\n", 0)

    assert_equal "/forums/1/path;stillpath/2375", @env["REQUEST_PATH"]
  end

  def test_keeps_bytes_outside_ascii_in_the_uri
    @parser.execute(@env, "GET /caf\xC3\xA9?x=\xFF HTTP/1.1\r\n\r\n".b, 0)

    assert_equal "/caf\xC3\xA9".b, @env["REQUEST_PATH"]
    assert_equal "x=\xFF".b, @env["QUERY_STRING"]
  end

  def test_returns_utf8_keys_and_binary_values
    @parser.execute(@env, "GET /a?b=c HTTP/1.1\r\nHost: h\r\nX-Unusual: u\r\n\r\n", 0)

    assert_equal [Encoding::UTF_8], @env.keys.map(&:encoding).uniq
    assert_equal [Encoding::BINARY], @env.values.map(&:encoding).uniq
  end

  def test_does_not_modify_the_buffer
    request = +"GET / HTTP/1.1\r\nHost-Name_x: y\r\n\r\n"
    @parser.execute(@env, request, 0)

    assert_equal "GET / HTTP/1.1\r\nHost-Name_x: y\r\n\r\n", request
  end

  # headers

  def test_accepts_unusual_header_names
    request = "GET / HTTP/1.1\r\naaaaaaaaaaaaa:++++++++++\r\n\r\n"

    assert_equal request.bytesize, @parser.execute(@env, request, 0)
    assert @parser.finished?
  end

  def test_trims_spaces_and_tabs_around_values
    @parser.execute(@env, "GET / HTTP/1.1\r\nX-Strip-Me: \t Strip This \t      \r\n\r\n", 0)

    assert_equal "Strip This", @env["HTTP_X_STRIP_ME"]
  end

  def test_keeps_a_tab_inside_a_value
    @parser.execute(@env, "GET / HTTP/1.1\r\nDummy: Valid\tValue\r\n\r\n", 0)

    assert_equal "Valid\tValue", @env["HTTP_DUMMY"]
  end

  def test_accepts_empty_values
    @parser.execute(@env, "GET / HTTP/1.1\r\nX-Empty:\r\nX-Spaces:   \r\nX-Tab:\tv\r\n\r\n", 0)

    assert_equal "", @env["HTTP_X_EMPTY"]
    assert_equal "", @env["HTTP_X_SPACES"]
    assert_equal "v", @env["HTTP_X_TAB"]
  end

  def test_joins_duplicate_headers_with_a_comma
    @parser.execute(@env, "GET / HTTP/1.1\r\nX-A: 1\r\nx-a: 2\r\n\r\n", 0)

    assert_equal "1, 2", @env["HTTP_X_A"]
  end

  # An underscore becomes a comma, so X_Forwarded_For can't impersonate
  # X-Forwarded-For.
  def test_turns_an_underscore_in_a_header_name_into_a_comma
    @parser.execute(@env, "GET / HTTP/1.1\r\nX_Forwarded_For: 1\r\nX-Forwarded-For: 2\r\n\r\n", 0)

    assert_equal "1", @env["HTTP_X,FORWARDED,FOR"]
    assert_equal "2", @env["HTTP_X_FORWARDED_FOR"]
  end

  def test_names_content_length_and_content_type_without_the_http_prefix
    @parser.execute(@env, "GET / HTTP/1.1\r\ncontent-length: 3\r\ncontent-type: t\r\n\r\nabc", 0)

    assert_equal "3", @env["CONTENT_LENGTH"]
    assert_equal "t", @env["CONTENT_TYPE"]
    refute @env.key?("HTTP_CONTENT_LENGTH")
  end

  # body

  def test_body_is_the_bytes_after_the_headers
    request = "GET / HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc"

    assert_equal request.bytesize - 3, @parser.execute(@env, request, 0)
    assert_equal "abc", @parser.body
  end

  def test_body_is_empty_when_nothing_follows_the_headers
    @parser.execute(@env, "GET / HTTP/1.1\r\n\r\n", 0)

    assert_equal "", @parser.body
  end

  # reset

  def test_reset_clears_the_parser_for_the_next_request
    @parser.execute(@env, "GET / HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc", 0)

    assert_nil @parser.reset
    assert_equal 0, @parser.nread
    assert_nil @parser.body
    refute @parser.finished?
  end

  # partial requests

  def test_resumes_where_the_previous_call_stopped
    buffer = +""
    nread = 0

    ["GET /ab", "c?d=1 HTTP/1.1\r\nHo", "st: x\r\n\r\nbody"].each do |chunk|
      refute @parser.finished?
      buffer << chunk
      nread = @parser.execute(@env, buffer, nread)
    end

    assert @parser.finished?
    assert_equal buffer.bytesize - "body".bytesize, nread
    assert_equal "/abc?d=1", @env["REQUEST_URI"]
    assert_equal "x", @env["HTTP_HOST"]
    assert_equal "body", @parser.body
  end

  def test_raises_when_a_later_part_is_invalid
    buffer = +"GET / HT"
    nread = @parser.execute(@env, buffer, 0)
    refute @parser.error?

    buffer << "TX"
    assert_raises(Puma::HttpParserError) { @parser.execute(@env, buffer, nread) }
    assert @parser.error?
    refute @parser.finished?
  end

  def test_raises_when_data_follows_a_finished_request
    buffer = +"GET / HTTP/1.1\r\n\r\n"
    nread = @parser.execute(@env, buffer, 0)

    buffer << "GET / HTTP/1.1\r\n\r\n"
    assert_raises(Puma::HttpParserError) { @parser.execute(@env, buffer, nread) }
    assert @parser.error?
  end

  def test_raises_when_start_is_at_or_after_the_end_of_the_data
    request = "GET / HTTP/1.1\r\n\r\n"

    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, request.bytesize) }
    assert_equal "Requested start is after data buffer end.", error.message
  end

  # invalid requests

  def test_raises_puma_http_parser_error_with_the_message_puma_looks_for
    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, "GET / SsUTF/1.1", 0) }

    assert_equal INVALID_FORMAT_MESSAGE, error.message
    assert @parser.error?
    refute @parser.finished?
  end

  def test_rejects_requests_that_do_not_follow_the_grammar
    [
      "get / HTTP/1.1\r\n\r\n",
      "GET abc HTTP/1.1\r\n\r\n",
      "GET  / HTTP/1.1\r\n\r\n",
      "GET / HTTP/1.\r\n\r\n",
      "GET / HTTP/1.1\n\n",
      "GET / HTTP/1.1\r\nX :1\r\n\r\n",
      "\x16\x03\x01\x02\x00\x01\x00\x01".b
    ].each do |request|
      parser = Puma::HTTP1::Parser.new
      error = assert_raises(Puma::HttpParserError, request.inspect) { parser.execute({}, request, 0) }

      assert_equal INVALID_FORMAT_MESSAGE, error.message, request.inspect
    end
  end

  # A bare LF could be used to smuggle a header past a proxy.
  def test_rejects_a_bare_lf_inside_the_headers
    request = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: x\nDummy2: y\r\n\r\n"

    assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, 0) }
  end

  def test_rejects_a_bare_lf_after_a_repeated_header
    request = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: x\r\nDummy: y\nDummy2: z\r\n\r\n"

    assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, 0) }
  end

  def test_rejects_random_garbage
    10.times do |c|
      uri = random_data(1024, 1024 + (c * 1024), readable: false)
      protocol = random_data(1024, 1024 + (c * 1024), readable: false)
      request = "GET #{uri} #{protocol}\r\n\r\n"

      assert_raises(Puma::HttpParserError) { @parser.execute({}, request, 0) }
      @parser.reset
    end
  end

  # length limits

  def test_allows_a_method_of_up_to_20_bytes
    @parser.execute(@env, "#{"A" * 20} / HTTP/1.1\r\n\r\n", 0)
    assert_equal "A" * 20, @env["REQUEST_METHOD"]

    @parser.reset
    assert_raises(Puma::HttpParserError) { @parser.execute({}, "#{"A" * 21} / HTTP/1.1\r\n\r\n", 0) }
  end

  def test_raises_pumas_message_when_a_header_name_is_too_long
    request = "GET / HTTP/1.1\r\n#{"a" * 257}: val\r\n\r\n"

    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, 0) }
    assert_equal "HTTP element FIELD_NAME is longer than the 256 allowed length (was 257)", error.message
  end

  def test_raises_pumas_message_when_a_header_value_is_too_long
    request = "GET / HTTP/1.1\r\ntest: #{"a" * ((80 * 1024) + 1)}\r\n\r\n"

    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, 0) }
    assert_equal "HTTP element FIELD_VALUE is longer than the 80 * 1024 allowed length (was 81921)", error.message
  end

  def test_raises_pumas_message_when_the_fragment_is_too_long
    request = "GET /##{"a" * 1025} HTTP/1.1\r\n\r\n"

    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, 0) }
    assert_equal "HTTP element FRAGMENT is longer than the 1024 allowed length (was 1025)", error.message
  end

  def test_raises_pumas_message_when_the_query_string_is_too_long
    request = "GET /?#{"a" * (5 * 1024)}=#{"b" * (5 * 1024)} HTTP/1.1\r\n\r\n"

    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, 0) }
    assert_equal "HTTP element QUERY_STRING is longer than the (1024 * 10) allowed length (was 10241)", error.message
  end

  def test_raises_pumas_message_when_the_request_path_is_too_long
    request = "GET /#{"a" * (8 * 1024)} HTTP/1.1\r\n\r\n"

    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, 0) }
    assert_equal "HTTP element REQUEST_PATH is longer than the (8192) allowed length (was 8193)", error.message
  end

  def test_raises_pumas_message_when_the_request_uri_is_too_long
    request = "GET /#{"a" * 6 * 1024}?#{"a" * 3 * 1024}=#{"a" * 3 * 1024} HTTP/1.1\r\n\r\n"

    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, request, 0) }
    assert_equal "HTTP element REQUEST_URI is longer than the (1024 * 12) allowed length (was 12291)", error.message
  end

  def test_raises_pumas_message_when_all_the_headers_together_are_too_long
    headers = "#{"a" * 256}: #{"a" * (2048 - 256)}\r\n" * 56

    error = assert_raises(Puma::HttpParserError) { @parser.execute(@env, "GET / HTTP/1.1\r\n#{headers}\r\n", 0) }
    assert_match(/\AHTTP element HEADER is longer than the \(1024 \* \(80 \+ 32\)\) allowed length/, error.message)
  end

  def test_accepts_a_path_under_the_limit_and_rejects_one_over_it
    path = "/#{random_data(7000, 100)}"
    @parser.execute(@env, "GET #{path} HTTP/1.1\r\n\r\n", 0)
    assert_equal path, @env["REQUEST_PATH"]

    @parser.reset
    path = "/#{random_data(9000, 100)}"
    assert_raises(Puma::HttpParserError) { @parser.execute({}, "GET #{path} HTTP/1.1\r\n\r\n", 0) }
  end

  def test_rejects_long_header_names_and_long_binary_values
    10.times do |c|
      long_name = random_data(1024, 1024 + (c * 1024))
      request = "GET /#{random_data(10, 120)} HTTP/1.1\r\nX-#{long_name}: Test\r\n\r\n"
      assert_raises(Puma::HttpParserError) { @parser.execute({}, request, 0) }
      @parser.reset

      binary_value = random_data(1024, 1024 + (c * 1024), readable: false)
      request = "GET /#{random_data(10, 120)} HTTP/1.1\r\nX-Test: #{binary_value}\r\n\r\n"
      assert_raises(Puma::HttpParserError) { @parser.execute({}, request, 0) }
      @parser.reset
    end
  end

  # fast paths

  # Each *_RUN_END regexp finds the end of a run of bytes in one call. It must
  # end the run exactly where its byte table does.
  def test_run_end_regexps_agree_with_the_byte_tables
    parser_class = Puma::HTTP1::Parser

    {
      parser_class::METHOD_BYTE => parser_class::METHOD_RUN_END,
      parser_class::SCHEME_BYTE => parser_class::SCHEME_RUN_END,
      parser_class::URI_BYTE => parser_class::URI_RUN_END,
      parser_class::PATH_BYTE => parser_class::PATH_RUN_END,
      parser_class::FIELD_NAME_BYTE => parser_class::FIELD_NAME_RUN_END,
      parser_class::FIELD_VALUE_BYTE => parser_class::FIELD_VALUE_RUN_END
    }.each do |table, run_end|
      256.times do |byte|
        assert_equal table[byte], !run_end.match?(byte.chr.b), "#{run_end.inspect} byte #{byte}"
      end
    end
  end

  # Only lines that HEADER_LINE rejects reach the byte by byte path, so it
  # must be exactly as strict as the byte tables.
  def test_header_line_regexp_agrees_with_the_byte_tables
    parser_class = Puma::HTTP1::Parser
    header_line = parser_class::HEADER_LINE

    256.times do |byte|
      name_line = "#{byte.chr}: v\r\n".b
      value_line = "X: a#{byte.chr}b\r\n".b

      assert_equal parser_class::FIELD_NAME_BYTE[byte], header_line.match?(name_line), "name byte #{byte}"
      assert_equal parser_class::FIELD_VALUE_BYTE[byte], header_line.match?(value_line), "value byte #{byte}"
    end

    assert_match header_line, "X:\r\n".b
    assert_match header_line, "X:   \tv \r\n".b
    refute_match header_line, "X : v\r\n".b
    refute_match header_line, ": v\r\n".b
    refute_match header_line, "X: v\n".b
  end
end
