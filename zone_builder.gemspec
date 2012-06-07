Gem::Specification.new do |s|
  s.name = 'zone_builder'
  s.version = '0.1.0'

  s.summary = 'Bind9 zone generation DSL'
  s.description = 'Define Bind9 zones in ruby and generate zonefiles with an updated serial number.'

  s.homepage = 'https://github.com/sagran/zonebuilder'
  s.author = 'Sergey Grankin'
  s.email = 'fntena@tznvy.pbz'.tr("A-Za-z", "N-ZA-Mn-za-m")

  s.files = `git ls-files`.split($/)
  s.has_rdoc = 'yard'
  s.license = 'MIT'

  s.add_development_dependency 'bundler'
end
