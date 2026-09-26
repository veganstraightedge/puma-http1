## [Unreleased]

- Write the tests in minitest, like Puma's own test suite, instead of RSpec

- Add `Puma::HTTP1::Parser`, a Ruby port of the HTTP parser in Puma's `puma_http11` C extension, for Puma's proposed `http_parser` option
- Add an example app that runs Puma with `Puma::HTTP1::Parser`, with and without `puma_http11`
- Add `script/benchmark`, comparing parsing time with `Puma::HttpParser`
- Add `script/benchmark-server`, comparing requests per second with ApacheBench, and the results of a run on Ruby 4.0.7
