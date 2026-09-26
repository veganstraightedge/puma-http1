# frozen_string_literal: true

require "digest"

RSpec.describe Puma::HTTP1::Parser do
  subject(:parser) { described_class.new }

  let(:env) { {} }

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

  describe "#execute" do
    it "parses a simple HTTP/1.1 request" do
      request = "GET /?a=1 HTTP/1.1\r\n\r\n"
      nread = parser.execute(env, request, 0)

      expect(nread).to eq request.bytesize
      expect(parser).to be_finished
      expect(parser).not_to be_error
      expect(parser.nread).to eq nread
      expect(env).to eq(
        "QUERY_STRING" => "a=1",
        "REQUEST_METHOD" => "GET",
        "REQUEST_PATH" => "/",
        "REQUEST_URI" => "/?a=1",
        "SERVER_PROTOCOL" => "HTTP/1.1"
      )
    end

    it "parses a simple HTTP/1.0 request" do
      parser.execute(env, "GET / HTTP/1.0\r\n\r\n", 0)

      expect(parser).to be_finished
      expect(env).to eq(
        "REQUEST_METHOD" => "GET",
        "REQUEST_PATH" => "/",
        "REQUEST_URI" => "/",
        "SERVER_PROTOCOL" => "HTTP/1.0"
      )
    end

    it "keeps escapes and a bare % in the query" do
      parser.execute(env, "GET /admin/users?search=%27%%27 HTTP/1.1\r\n\r\n", 0)

      expect(env["REQUEST_URI"]).to eq "/admin/users?search=%27%%27"
      expect(env["QUERY_STRING"]).to eq "search=%27%%27"
    end

    it "leaves the path and query of an absolute URI to Puma" do
      parser.execute(env, "GET http://192.168.1.96:3000/api/v1/matches/test?1=1 HTTP/1.1\r\n\r\n", 0)

      expect(env["REQUEST_URI"]).to eq "http://192.168.1.96:3000/api/v1/matches/test?1=1"
      expect(env).not_to include("REQUEST_PATH", "QUERY_STRING", "FRAGMENT")
    end

    it "parses * as the request URI" do
      parser.execute(env, "OPTIONS * HTTP/1.1\r\n\r\n", 0)

      expect(env["REQUEST_METHOD"]).to eq "OPTIONS"
      expect(env["REQUEST_URI"]).to eq "*"
      expect(env).not_to include("REQUEST_PATH")
    end

    it "separates the fragment from the request URI" do
      parser.execute(env, "GET /forums/1/topics/2375?page=1#posts-17408 HTTP/1.1\r\n\r\n", 0)

      expect(env["REQUEST_URI"]).to eq "/forums/1/topics/2375?page=1"
      expect(env["FRAGMENT"]).to eq "posts-17408"
    end

    it "allows a semicolon in the path" do
      parser.execute(env, "GET /forums/1/path;stillpath/2375?page=1 HTTP/1.1\r\n\r\n", 0)

      expect(env["REQUEST_PATH"]).to eq "/forums/1/path;stillpath/2375"
    end

    it "keeps bytes outside ASCII in the URI" do
      parser.execute(env, "GET /caf\xC3\xA9?x=\xFF HTTP/1.1\r\n\r\n".b, 0)

      expect(env["REQUEST_PATH"]).to eq "/caf\xC3\xA9".b
      expect(env["QUERY_STRING"]).to eq "x=\xFF".b
    end

    it "returns UTF-8 keys and binary values" do
      parser.execute(env, "GET /a?b=c HTTP/1.1\r\nHost: h\r\nX-Unusual: u\r\n\r\n", 0)

      expect(env.keys.map(&:encoding).uniq).to eq [Encoding::UTF_8]
      expect(env.values.map(&:encoding).uniq).to eq [Encoding::BINARY]
    end

    it "does not modify the buffer" do
      request = +"GET / HTTP/1.1\r\nHost-Name_x: y\r\n\r\n"
      parser.execute(env, request, 0)

      expect(request).to eq "GET / HTTP/1.1\r\nHost-Name_x: y\r\n\r\n"
    end
  end

  describe "headers" do
    it "accepts unusual header names" do
      request = "GET / HTTP/1.1\r\naaaaaaaaaaaaa:++++++++++\r\n\r\n"

      expect(parser.execute(env, request, 0)).to eq request.bytesize
      expect(parser).to be_finished
    end

    it "trims spaces and tabs around values" do
      parser.execute(env, "GET / HTTP/1.1\r\nX-Strip-Me: \t Strip This \t      \r\n\r\n", 0)

      expect(env["HTTP_X_STRIP_ME"]).to eq "Strip This"
    end

    it "keeps a tab inside a value" do
      parser.execute(env, "GET / HTTP/1.1\r\nDummy: Valid\tValue\r\n\r\n", 0)

      expect(env["HTTP_DUMMY"]).to eq "Valid\tValue"
    end

    it "accepts empty values" do
      parser.execute(env, "GET / HTTP/1.1\r\nX-Empty:\r\nX-Spaces:   \r\nX-Tab:\tv\r\n\r\n", 0)

      expect(env).to include("HTTP_X_EMPTY" => "", "HTTP_X_SPACES" => "", "HTTP_X_TAB" => "v")
    end

    it "joins duplicate headers with a comma" do
      parser.execute(env, "GET / HTTP/1.1\r\nX-A: 1\r\nx-a: 2\r\n\r\n", 0)

      expect(env["HTTP_X_A"]).to eq "1, 2"
    end

    it "turns an underscore in a name into a comma, so it can't impersonate a dash" do
      parser.execute(env, "GET / HTTP/1.1\r\nX_Forwarded_For: 1\r\nX-Forwarded-For: 2\r\n\r\n", 0)

      expect(env).to include("HTTP_X,FORWARDED,FOR" => "1", "HTTP_X_FORWARDED_FOR" => "2")
    end

    it "names Content-Length and Content-Type without the HTTP_ prefix" do
      parser.execute(env, "GET / HTTP/1.1\r\ncontent-length: 3\r\ncontent-type: t\r\n\r\nabc", 0)

      expect(env).to include("CONTENT_LENGTH" => "3", "CONTENT_TYPE" => "t")
      expect(env).not_to include("HTTP_CONTENT_LENGTH")
    end
  end

  describe "#body" do
    it "is the bytes after the headers" do
      request = "GET / HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc"

      expect(parser.execute(env, request, 0)).to eq request.bytesize - 3
      expect(parser.body).to eq "abc"
    end

    it "is empty when nothing follows the headers" do
      parser.execute(env, "GET / HTTP/1.1\r\n\r\n", 0)

      expect(parser.body).to eq ""
    end
  end

  describe "#reset" do
    it "clears the parser for the next request" do
      parser.execute(env, "GET / HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc", 0)

      expect(parser.reset).to be_nil
      expect(parser.nread).to eq 0
      expect(parser.body).to be_nil
      expect(parser).not_to be_finished
    end
  end

  describe "partial requests" do
    it "resumes where the previous call stopped" do
      buffer = +""
      nread = 0

      ["GET /ab", "c?d=1 HTTP/1.1\r\nHo", "st: x\r\n\r\nbody"].each do |chunk|
        expect(parser).not_to be_finished
        buffer << chunk
        nread = parser.execute(env, buffer, nread)
      end

      expect(parser).to be_finished
      expect(nread).to eq buffer.bytesize - "body".bytesize
      expect(env).to include("REQUEST_URI" => "/abc?d=1", "HTTP_HOST" => "x")
      expect(parser.body).to eq "body"
    end

    it "raises when a later part is invalid" do
      buffer = +"GET / HT"
      nread = parser.execute(env, buffer, 0)
      expect(parser).not_to be_error

      buffer << "TX"
      expect { parser.execute(env, buffer, nread) }.to raise_error Puma::HttpParserError
      expect(parser).to be_error
      expect(parser).not_to be_finished
    end

    it "raises when data follows a finished request" do
      buffer = +"GET / HTTP/1.1\r\n\r\n"
      nread = parser.execute(env, buffer, 0)

      buffer << "GET / HTTP/1.1\r\n\r\n"
      expect { parser.execute(env, buffer, nread) }.to raise_error Puma::HttpParserError
      expect(parser).to be_error
    end

    it "raises when start is at or after the end of the data" do
      request = "GET / HTTP/1.1\r\n\r\n"

      expect { parser.execute(env, request, request.bytesize) }
        .to raise_error Puma::HttpParserError, "Requested start is after data buffer end."
    end
  end

  describe "invalid requests" do
    let(:message) { "Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?" }

    it "raises Puma::HttpParserError with the message Puma looks for" do
      expect { parser.execute(env, "GET / SsUTF/1.1", 0) }.to raise_error Puma::HttpParserError, message
      expect(parser).to be_error
      expect(parser).not_to be_finished
    end

    [
      "get / HTTP/1.1\r\n\r\n",
      "GET abc HTTP/1.1\r\n\r\n",
      "GET  / HTTP/1.1\r\n\r\n",
      "GET / HTTP/1.\r\n\r\n",
      "GET / HTTP/1.1\n\n",
      "GET / HTTP/1.1\r\nX :1\r\n\r\n",
      "\x16\x03\x01\x02\x00\x01\x00\x01".b
    ].each do |request|
      it "rejects #{request.inspect}" do
        expect { parser.execute(env, request, 0) }.to raise_error Puma::HttpParserError, message
      end
    end

    it "rejects a bare LF inside the headers, which could smuggle a header" do
      request = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: x\nDummy2: y\r\n\r\n"

      expect { parser.execute(env, request, 0) }.to raise_error Puma::HttpParserError
    end

    it "rejects a bare LF after a repeated header" do
      request = "GET / HTTP/1.1\r\nHost: localhost:8080\r\nDummy: x\r\nDummy: y\nDummy2: z\r\n\r\n"

      expect { parser.execute(env, request, 0) }.to raise_error Puma::HttpParserError
    end

    it "rejects random garbage" do
      10.times do |c|
        uri = random_data(1024, 1024 + (c * 1024), readable: false)
        protocol = random_data(1024, 1024 + (c * 1024), readable: false)
        request = "GET #{uri} #{protocol}\r\n\r\n"

        expect { parser.execute({}, request, 0) }.to raise_error Puma::HttpParserError
        parser.reset
      end
    end
  end

  describe "length limits" do
    it "allows a method of up to 20 bytes" do
      parser.execute(env, "#{"A" * 20} / HTTP/1.1\r\n\r\n", 0)
      expect(env["REQUEST_METHOD"]).to eq "A" * 20

      parser.reset
      expect { parser.execute({}, "#{"A" * 21} / HTTP/1.1\r\n\r\n", 0) }.to raise_error Puma::HttpParserError
    end

    {
      "FIELD_NAME" => ["GET / HTTP/1.1\r\n#{"a" * 257}: val\r\n\r\n",
                       "HTTP element FIELD_NAME is longer than the 256 allowed length (was 257)"],
      "FIELD_VALUE" => ["GET / HTTP/1.1\r\ntest: #{"a" * ((80 * 1024) + 1)}\r\n\r\n",
                        "HTTP element FIELD_VALUE is longer than the 80 * 1024 allowed length (was 81921)"],
      "FRAGMENT" => ["GET /##{"a" * 1025} HTTP/1.1\r\n\r\n",
                     "HTTP element FRAGMENT is longer than the 1024 allowed length (was 1025)"],
      "QUERY_STRING" => ["GET /?#{"a" * (5 * 1024)}=#{"b" * (5 * 1024)} HTTP/1.1\r\n\r\n",
                         "HTTP element QUERY_STRING is longer than the (1024 * 10) allowed length (was 10241)"],
      "REQUEST_PATH" => ["GET /#{"a" * (8 * 1024)} HTTP/1.1\r\n\r\n",
                         "HTTP element REQUEST_PATH is longer than the (8192) allowed length (was 8193)"],
      "REQUEST_URI" => ["GET /#{"a" * 6 * 1024}?#{"a" * 3 * 1024}=#{"a" * 3 * 1024} HTTP/1.1\r\n\r\n",
                        "HTTP element REQUEST_URI is longer than the (1024 * 12) allowed length (was 12291)"]
    }.each do |element, (request, message)|
      it "raises Puma's message when #{element} is too long" do
        expect { parser.execute(env, request, 0) }.to raise_error Puma::HttpParserError, message
      end
    end

    it "raises Puma's message when all the headers together are too long" do
      headers = "#{"a" * 256}: #{"a" * (2048 - 256)}\r\n" * 56

      expect { parser.execute(env, "GET / HTTP/1.1\r\n#{headers}\r\n", 0) }
        .to raise_error Puma::HttpParserError,
                        /\AHTTP element HEADER is longer than the \(1024 \* \(80 \+ 32\)\) allowed length/
    end

    it "accepts a path under the limit and rejects one over it" do
      path = "/#{random_data(7000, 100)}"
      parser.execute(env, "GET #{path} HTTP/1.1\r\n\r\n", 0)
      expect(env["REQUEST_PATH"]).to eq path

      parser.reset
      path = "/#{random_data(9000, 100)}"
      expect { parser.execute({}, "GET #{path} HTTP/1.1\r\n\r\n", 0) }.to raise_error Puma::HttpParserError
    end

    it "rejects long header names and long binary values" do
      10.times do |c|
        long_name = random_data(1024, 1024 + (c * 1024))
        request = "GET /#{random_data(10, 120)} HTTP/1.1\r\nX-#{long_name}: Test\r\n\r\n"
        expect { parser.execute({}, request, 0) }.to raise_error Puma::HttpParserError
        parser.reset

        binary_value = random_data(1024, 1024 + (c * 1024), readable: false)
        request = "GET /#{random_data(10, 120)} HTTP/1.1\r\nX-Test: #{binary_value}\r\n\r\n"
        expect { parser.execute({}, request, 0) }.to raise_error Puma::HttpParserError
        parser.reset
      end
    end
  end

  describe "fast paths" do
    {
      METHOD_BYTE: :METHOD_RUN_END,
      SCHEME_BYTE: :SCHEME_RUN_END,
      URI_BYTE: :URI_RUN_END,
      PATH_BYTE: :PATH_RUN_END,
      FIELD_NAME_BYTE: :FIELD_NAME_RUN_END,
      FIELD_VALUE_BYTE: :FIELD_VALUE_RUN_END
    }.each do |table_name, run_end_name|
      it "#{run_end_name} ends a run exactly where #{table_name} does" do
        table = described_class.const_get(table_name)
        run_end = described_class.const_get(run_end_name)

        256.times do |byte|
          expect(!run_end.match?(byte.chr.b)).to eq(table[byte]), "byte #{byte}"
        end
      end
    end

    # Only lines that HEADER_LINE rejects reach the byte by byte path, so it
    # must be exactly as strict as the byte tables.
    it "matches whole header lines exactly as strictly as the byte tables" do
      header_line = described_class::HEADER_LINE

      256.times do |byte|
        name_line = "#{byte.chr}: v\r\n".b
        value_line = "X: a#{byte.chr}b\r\n".b

        expect(header_line.match?(name_line)).to eq(described_class::FIELD_NAME_BYTE[byte]), "name byte #{byte}"
        expect(header_line.match?(value_line)).to eq(described_class::FIELD_VALUE_BYTE[byte]), "value byte #{byte}"
      end

      expect(header_line).to match "X:\r\n".b
      expect(header_line).to match "X:   \tv \r\n".b
      expect(header_line).not_to match "X : v\r\n".b
      expect(header_line).not_to match ": v\r\n".b
      expect(header_line).not_to match "X: v\n".b
    end
  end
end
