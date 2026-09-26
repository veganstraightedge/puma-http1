# puma-http

An HTTP parser for [Puma](https://github.com/puma/puma), written in Ruby.

`Puma::HTTP::Parser` is a drop-in for `Puma::HttpParser`, the parser in Puma's `puma_http11` C extension. It follows the same Ragel grammar state for state, fills the same env keys, enforces the same length limits, and raises the same errors with the same messages. The specs run every request through both parsers and expect the same result.

With it, Puma can run where its C extension can't be built or loaded.

## Status

This is a reference implementation for a proposed `http_parser` option in Puma. That option isn't in a Puma release, so this gem needs Puma from the `pluggable-http-parser` branch of [veganstraightedge/puma](https://github.com/veganstraightedge/puma/tree/pluggable-http-parser). The gem isn't published to RubyGems.org.

## Installation

```ruby
# Gemfile
gem "puma", github: "veganstraightedge/puma", branch: "pluggable-http-parser"
gem "puma-http", github: "veganstraightedge/puma-http"
```

## Usage

Require the gem and pass the parser class to Puma's `http_parser` option.

```ruby
# config/puma.rb
require "puma/http"

http_parser Puma::HTTP::Parser
```

Puma's [HTTP parser documentation](https://github.com/veganstraightedge/puma/blob/pluggable-http-parser/docs/http_parser.md) describes the interface a parser has to follow.

### Without the C extension

When Puma's `puma_http11` extension can't be loaded, Puma still starts, as long as `http_parser` is set. SSL isn't available then, because Puma's SSL support is in the same extension.

The [example app](example) runs both ways:

```
$ script/example
=== With puma_http11 installed ===
HTTP parser: Puma::HTTP::Parser
puma_http11: loaded
...

=== With puma_http11 hidden ===
HTTP parser: Puma::HTTP::Parser
puma_http11: not loaded
...
```

## Differences from Puma::HttpParser

The C parser upcases header names inside the request buffer as it parses. This parser leaves the buffer alone. So when Puma reports a request with bad headers, the error message shows the header names as the client sent them. Puma's Java parser, used on JRuby, behaves the same way.

## Performance

It's slower than the C parser. Microseconds per parse on an Apple M1, from `script/benchmark`:

| request                 | Puma::HttpParser | Puma::HTTP::Parser | Puma::HTTP::Parser with YJIT |
|:------------------------|-----------------:|-------------------:|-----------------------------:|
| minimal GET             |             0.44 |               3.14 |                         1.56 |
| browser GET, 13 headers |             2.76 |              17.05 |                        15.53 |
| API POST, 7 headers     |             1.55 |              10.50 |                         7.12 |

That's roughly 5 to 15 µs more per request. In a hello world app, that means 16 to 29 percent fewer requests per second. In an app doing real work per request, it should be a small fraction of the total.

## Development

```
script/setup      # install dependencies, for the gem and the example app
script/test       # run the specs and RuboCop
script/example    # run the example app with and without puma_http11
script/server     # run the example app on port 9292
script/benchmark  # compare parsing time with Puma::HttpParser
script/console    # start IRB with the gem loaded
```

## License

BSD 3-Clause, the same as Puma. The parser is ported from Puma's C extension, so the license keeps Puma's copyright notice. See [LICENSE.txt](LICENSE.txt).
