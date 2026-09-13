require 'grimoire'

module FixtureHelpers
  FIXTURE_DIR = File.expand_path('fixtures', __dir__)

  # Fixture files carry leading/inline "<!-- ... -->" citation comments
  # documenting where each excerpt was captured from -- real Lich stream
  # data never contains XML comments, so stripping them here is a fixture-
  # loading concern only, not something the tokenizer itself needs to
  # handle.
  def fixture(name)
    raw = File.read(File.join(FIXTURE_DIR, name))
    raw.gsub(/<!--.*?-->/m, '')
  end
end

RSpec.configure do |config|
  config.include FixtureHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
