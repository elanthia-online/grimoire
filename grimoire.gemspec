require_relative 'lib/grimoire/version'

Gem::Specification.new do |spec|
  spec.name        = 'grimoire'
  spec.version     = Grimoire::VERSION
  spec.authors     = ['Elanthia Online']
  spec.summary     = 'A lightweight Ruby/GTK3 front-end for Simutronics text-based games'
  spec.description = 'Grimoire attaches to lich-5 frontend socket as a display-and-input ' \
                      'client for GemStone IV and DragonRealms, in the spirit of ProfanityFE ' \
                      'but built on GTK3.'
  spec.homepage    = 'https://github.com/elanthia-online/grimoire'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 4.0'

  spec.files         = Dir['lib/**/*.rb'] + ['grimoire']
  spec.require_paths = ['lib']

  spec.add_dependency 'gtk3', '~> 4.3'

  spec.add_development_dependency 'rspec',   '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.75'
end
