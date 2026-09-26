# frozen_string_literal: true

require_relative "lib/puma/http1/version"

Gem::Specification.new do |spec|
  spec.name = "puma-http1"
  spec.version = Puma::HTTP1::VERSION
  spec.authors = ["Shane Becker"]
  spec.email = ["veganstraightedge@gmail.com"]

  spec.summary = "An HTTP parser for Puma, written in Ruby."
  spec.description = "A drop-in for the HTTP parser in Puma's puma_http11 C extension, " \
                     "for use with Puma's http_parser option."
  spec.homepage = "https://github.com/veganstraightedge/puma-http1"
  spec.license = "BSD-3-Clause"
  spec.required_ruby_version = ">= 3.4.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/veganstraightedge/puma-http1"
  spec.metadata["changelog_uri"] = "https://github.com/veganstraightedge/puma-http1/blob/main/CHANGELOG.md"

  # Require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml example/ script/ .ruby-version])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "puma"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
