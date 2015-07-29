if RUBY_VERSION > "1.9"
  require 'simplecov'
  require 'simplecov-gem-profile'
  SimpleCov.start 'gem'
end

require 'rspec'
require 'defog'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

RSpec.configure do |config|
  config.include Helpers
end

RSPEC_TMP_PATH = Pathname.new(__FILE__).dirname + "tmp"
PROXY_BASE_PATH = RSPEC_TMP_PATH + "proxy"
LOCAL_CLOUD_PATH = RSPEC_TMP_PATH + "cloud"
RAILS_ROOT_PATH = RSPEC_TMP_PATH + "railsapp"

[PROXY_BASE_PATH, LOCAL_CLOUD_PATH, RAILS_ROOT_PATH].each do |path|
  path.rmtree if path.exist?
  path.mkpath
end

