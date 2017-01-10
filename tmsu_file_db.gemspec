require_relative './lib/version.rb'
Gem::Specification.new do |s|
  s.name        = "tmsu_file_db"
  s.version     = TmsuFileDb::VERSION
  s.date        = "2017-01-08"
  s.summary     = "a 'database' using TMSU file tagging system"
  s.description = ""
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["maxpleaner"]
  s.email       = 'maxpleaner@gmail.com'
  s.required_ruby_version = '~> 2.3'
  s.homepage    = "http://github.com/maxpleaner/tmsu_file_db"
  s.files       = Dir["lib/**/*.rb", "bin/*", "**/*.md", "LICENSE"]
  s.require_path = 'lib'
  s.required_rubygems_version = ">= 2.5.1"
  s.executables = Dir["bin/*"].map &File.method(:basename)
  s.add_dependency 'gemmyrb'
  s.license     = 'MIT'
end
