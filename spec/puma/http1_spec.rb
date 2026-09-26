# frozen_string_literal: true

require "puma"
require "puma/const"

RSpec.describe Puma::HTTP1 do
  it "has a version number" do
    expect(Puma::HTTP1::VERSION).to eq "0.1.0"
  end

  # Puma's code refers to Puma::Const constants without the Const:: prefix,
  # so a constant of the same name directly under Puma would be found first.
  it "doesn't shadow a Puma::Const constant" do
    gem_constants = %i[HTTP1 HttpParserError]

    expect(Puma::Const.constants & gem_constants).to be_empty
  end
end
