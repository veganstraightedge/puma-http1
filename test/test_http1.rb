# frozen_string_literal: true

require_relative "helper"
require "puma"
require "puma/const"

class TestHTTP1 < Minitest::Test
  def test_version
    assert_equal "0.0.1", Puma::HTTP1::VERSION
  end

  # Puma's code refers to Puma::Const constants without the Const:: prefix,
  # so a constant of the same name directly under Puma would be found first.
  def test_does_not_shadow_a_puma_const_constant
    gem_constants = %i[HTTP1 HttpParserError]

    assert_empty Puma::Const.constants & gem_constants
  end
end
