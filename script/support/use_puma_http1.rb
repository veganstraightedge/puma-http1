# frozen_string_literal: true

# Loaded by script/test-puma-suite, before Puma's test suite, to make every
# Puma::Server and Puma::Client use Puma::HTTP1::Parser by default, instead
# of Puma::HttpParser from Puma's C extension. It doesn't change Puma's files.

require "puma"
require "puma/server"
require "puma/client"
require "puma/http1"

module UsePumaHTTP1
  # A server uses the parser set with the http_parser option, or this default.
  module ForServers
    private

    def default_http_parser
      Puma::HTTP1::Parser
    end
  end

  # Some of Puma's tests create a Puma::Client directly, without a server.
  module ForClients
    def initialize(io, env = nil, http_parser: Puma::HTTP1::Parser)
      super
    end
  end
end

Puma::Server.prepend(UsePumaHTTP1::ForServers)
Puma::Client.prepend(UsePumaHTTP1::ForClients)
