# puma-http1

An HTTP/1.x parser for [Puma](https://github.com/puma/puma), written in Ruby.

`Puma::HTTP1::Parser` is a drop-in for `Puma::HttpParser`, the parser in Puma’s `puma_http11` C extension. It follows the same Ragel grammar state for state, fills the same env keys, enforces the same length limits, and raises the same errors with the same messages. The tests run every request through both parsers and expect the same result.

With it, Puma can run where its C extension can't be built or loaded.

## Status

This is a reference implementation for a proposed `http_parser` option in Puma. That option isn't in a Puma release, so this gem needs Puma from the `pluggable-http-parser` branch of [veganstraightedge/puma](https://github.com/veganstraightedge/puma/tree/pluggable-http-parser). The gem isn't published to RubyGems.org.

## Installation

```ruby
# Gemfile
gem 'puma',       github: 'veganstraightedge/puma', branch: 'pluggable-http-parser'
gem 'puma-http1', github: 'veganstraightedge/puma-http1'
```

## Usage

Require the gem and pass the parser class to Puma’s `http_parser` option.

```ruby
# config/puma.rb
require 'puma/http1'

http_parser Puma::HTTP1::Parser
```

Puma’s [HTTP parser documentation](https://github.com/veganstraightedge/puma/blob/pluggable-http-parser/docs/http_parser.md) describes the interface a parser has to follow.

The gem is named `puma-http1`, and the module `Puma::HTTP1`, rather than `Puma::HTTP`, because `Puma::Const::HTTP` already exists. Puma’s code refers to it without the `Const::` prefix, so a `Puma::HTTP` module would be found first and break Puma.

### Without the C extension

When Puma’s `puma_http11` extension can't be loaded, Puma still starts, as long as `http_parser` is set. SSL isn't available then, because Puma’s SSL support is in the same extension.

The [example app](example) runs both ways:

```sh
$ script/example
=== With puma_http11 installed ===
HTTP parser: Puma::HTTP1::Parser
puma_http11: loaded
...

=== With puma_http11 hidden ===
HTTP parser: Puma::HTTP1::Parser
puma_http11: not loaded
...
```

## Differences from Puma::HttpParser

The C parser upcases header names inside the request buffer as it parses. This parser leaves the buffer alone. So when Puma reports a request with bad headers, the error message shows the header names as the client sent them. Puma’s Java parser, used on JRuby, also leaves the buffer alone, so this parser matches JRuby here.

## Performance

It’s slower than the C parser. On an Apple M1 with Ruby 4.0.7, from [`script/benchmark`](script/benchmark):

| request                 | Puma::HttpParser | Puma::HTTP1::Parser | Puma::HTTP1::Parser with YJIT |
| :---------------------- | ---------------: | ------------------: | ----------------------------: |
| minimal GET             |             0.46 |                3.19 |                          2.79 |
| browser GET, 13 headers |             2.81 |               17.18 |                         16.20 |
| API POST, 7 headers     |             1.56 |               10.53 |                          9.92 |

All values are microseconds per parse. Smaller is better.

That’s roughly 2 to 14 µs more per request. A hello world app, with keep-alive and 4 threads, serves this many requests per second, from [`script/benchmark-server`](script/benchmark-server) using [ApacheBench](https://httpd.apache.org/docs/current/programs/ab.html):

| request   | JIT  | Puma::HttpParser | Puma::HTTP1::Parser |  gap |
| :-------- | :--- | ---------------: | ------------------: | ---: |
| minimal   | none |           26,815 |              23,009 | -14% |
| 9 headers | none |           25,145 |              18,500 | -26% |
| minimal   | YJIT |           30,234 |              26,998 | -11% |
| 9 headers | YJIT |           28,270 |              22,323 | -21% |

All values are requests per second, except the gap, which is how much slower `Puma::HTTP1::Parser` is. Larger is better for requests per second. Smaller is better for the gap.

In an app doing real work per request, the difference should be a small fraction of the total.

The complete output of these runs, with every sample, the commits measured, and the machine's load, is in [benchmarks/2026-09-26-ruby-4.0.7.md](benchmarks/2026-09-26-ruby-4.0.7.md).

## Development

```sh
script/setup             # install dependencies, for the gem and the example app
script/test              # run the tests and RuboCop
script/example           # run the example app with and without puma_http11
script/server            # run the example app on port 9292
script/benchmark         # compare parsing time with Puma::HttpParser
script/benchmark-server  # compare requests per second, with ApacheBench
script/console           # start IRB with the gem loaded
```

## License

BSD 3-Clause, the same as Puma. The parser is ported from Puma’s C extension, so the license keeps Puma’s copyright notice. See [LICENSE.txt](LICENSE.txt).
