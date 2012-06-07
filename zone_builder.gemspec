require File.expand_path('../lib/zone_builder/version', __FILE__)
Gem::Specification.new do |gem|
  gem.authors = ['Sergey Grankin']
  gem.email = 'fntena@tznvy.pbz'.tr("A-Za-z", "N-ZA-Mn-za-m")

  gem.name = 'zone_builder'
  gem.homepage = 'https://github.com/sagran/zonebuilder'
  gem.summary = 'Bind9 zone generation DSL'
  gem.description = 'Define Bind9 zones in ruby and generate zonefiles with an updated serial number.'
  gem.license = 'MIT'

  gem.version = ZoneBuilder::VERSION

  gem.files = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']
  gem.has_rdoc = 'yard'

  gem.add_development_dependency 'bundler'
end
