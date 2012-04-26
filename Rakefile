#!/usr/bin/env rake
require "bundler/gem_tasks"

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.rspec_opts = '-Ispec'
end

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
    require File.dirname(__FILE__) + '/lib/defog/version'
    rdoc.rdoc_dir = 'rdoc'
    rdoc.title = "defog #{Defog::VERSION}"
    rdoc.rdoc_files.include('README*')
    rdoc.rdoc_files.include('lib/**/*.rb')
end
