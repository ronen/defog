require "fog"
require "hash_keyword_args"
require "pathname"

module Defog #:nodoc: all
  class FogWrapper #:nodoc: all

    attr_reader :location
    attr_reader :fog_directory

    def self.connect(opts={})
      opts = opts.keyword_args(:provider => :required, :OTHERS => :optional)
      provider = opts.delete(:provider)
      klass = begin
                self.const_get(provider.to_s.capitalize, false)
              rescue NameError
                raise ArgumentError, "#{provider.inspect} is not a supported fog storage provider"
              end
      klass.new(opts)
    end

    def get_file(key, path)
      raise Error::NoCloudFile, "No such file in #{provider} #{location}: #{key}" unless fog_head(key)
      return if path.exist? and Digest::MD5.hexdigest(path.read) == get_md5(key)
      path.open("w") do |f|
        f.write(fog_head(key).body)
      end
    end

    def put_file(key, path)
      fog_directory.files.create(:key => key, :body => path.open)
    end

    def fog_head(key)
      fog_directory.files.head(key)
    end

    class Local < FogWrapper
      def provider ; :local ; end

      def initialize(opts={})
        opts = opts.keyword_args(:local_root => :required)
        directory = Pathname.new(opts.local_root).realpath
        @location = directory.to_s.gsub(%r{/},'_')
        @fog_connection = Fog::Storage.new(:provider => provider, :local_root => directory)
        @fog_directory = @fog_connection.directories.get('.')
      end

      def get_md5(key)
        Digest::MD5.hexdigest(fog_head(key).body)
      end

    end

    class Aws < FogWrapper
      def provider ; :AWS ; end

      def initialize(opts={})
        opts = opts.keyword_args(:aws_access_key_id => :required, :aws_secret_access_key => :required, :region => :optional, :bucket => :required)
        @location = opts.delete(:bucket)
        @fog_connection = Fog::Storage.new(opts.merge(:provider => provider))
        @fog_connection.directories.create :key => @location unless @fog_connection.directories.map(&:key).include? @location
        @fog_directory = @fog_connection.directories.get(@location)
      end

      def get_md5(key)
        fog_head(key).content_md5
      end

    end
  end
end

