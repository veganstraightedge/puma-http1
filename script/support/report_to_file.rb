# frozen_string_literal: true

require "minitest"

# Loaded by script/test-puma-suite, before Puma's test suite. Writes minitest's
# summary, with the details of each failure, to the file named in
# PUMA_HTTP1_RESULTS, so the summary survives tests that redirect or close
# standard output.
module Minitest
  def self.plugin_puma_http1_results_init(options)
    # The file stays open until the process exits, so minitest can write the
    # summary at the end of the run.
    results = File.open(ENV.fetch("PUMA_HTTP1_RESULTS"), "w") # rubocop:disable Style/FileOpen
    results.sync = true
    reporter << SummaryReporter.new(results, options)
  end
end

Minitest.extensions << "puma_http1_results"
