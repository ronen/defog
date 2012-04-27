# -*- encoding: utf-8 -*-
require File.expand_path('../lib/defog/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["ronen barzel"]
  gem.email         = ["ronen@barzel.org"]
  gem.description   = %q{Wrapper to fog gem, proxying access to cloud files as local files.}
  gem.summary       = %q{Wrapper to fog gem, proxying access to cloud files as local files.  Access can be read-only (local cache), write-only (upload), or read-write (mirror)}
  gem.homepage      = "http://github.com/ronen/defog"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = "defog"
  gem.require_paths = ["lib"]
  gem.version       = Defog::VERSION

  gem.add_dependency 'fog'
  gem.add_dependency 'hash_keyword_args'
  gem.add_dependency 'fastandand'

  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'simplecov'
  gem.add_development_dependency 'simplecov-gem-adapter'
end
