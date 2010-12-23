require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "girror"
  gem.homepage = "http://github.com/argent-smith/girror"
  gem.license = "MIT"
  gem.summary = %Q{Remote -> local directory 'mirror' using SFTP transport and Git storage.}
  gem.description = %Q{Retrieves remote directory via SFTP and stores it in local Git repository.}
  gem.email = "argentoff@gmail.com"
  gem.authors = ["Pavel Argentov"]
  # Include your dependencies below. Runtime dependencies are required when using your gem,
  # and development dependencies are only needed for development (ie running rake tasks, tests, etc)
  #  gem.add_runtime_dependency 'jabber4r', '> 0.1'
  #  gem.add_development_dependency 'rspec', '> 1.2.3'
  gem.add_runtime_dependency 'net-sftp'
  gem.add_runtime_dependency 'git'
  gem.add_runtime_dependency 'highline'
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "girror #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
