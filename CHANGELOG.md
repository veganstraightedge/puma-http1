## [Unreleased]

- Add `Puma::HTTP::Parser`, a Ruby port of the HTTP parser in Puma's `puma_http11` C extension, for Puma's proposed `http_parser` option
- Add an example app that runs Puma with `Puma::HTTP::Parser`, with and without `puma_http11`
- Add `script/benchmark`, comparing parsing time with `Puma::HttpParser`
