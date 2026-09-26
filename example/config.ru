# frozen_string_literal: true

# Responds with the HTTP parser Puma is using, whether Puma's puma_http11
# extension is loaded, and a few values the parser read from the request.
run lambda { |env|
  http_parser = env["puma.config"].options[:http_parser] || "Puma::HttpParser"
  puma_http11 = Puma.const_defined?(:HttpParser, false) ? "loaded" : "not loaded"

  body = <<~TEXT
    HTTP parser: #{http_parser}
    puma_http11: #{puma_http11}
    Method: #{env["REQUEST_METHOD"]}
    Path: #{env["PATH_INFO"]}
    Query: #{env["QUERY_STRING"]}
    User agent: #{env["HTTP_USER_AGENT"]}
  TEXT

  [200, { "content-type" => "text/plain" }, [body]]
}
