require "hash_keyword_args"
require "tmpdir"
require "pathname"

module Defog
  class Proxy

    attr_reader :proxy_root     # 
    attr_reader :fog_wrapper    # :nodoc:

    # Opens a <code>Fog</code> cloud storage connection to map to a corresponding proxy
    # directory.  Use via, e.g.,
    #
    #     Defog::Proxy.new(:provider => :AWS, :aws_access_key_id => access_key, ...)
    #
    # The <code>:provider</code> and its corresponding options must be
    # specified as per <code>Fog::Storage.new</code>.  Currently, only
    # <code>:local</code> and <code>:AWS</code> are supported.  When using
    # <code>:AWS</code>, an additional option <code>:bucket</code> must be
    # specified; all files proxied by this instance must be in a single
    # bucket.
    #
    # By default, each proxy's root directory is placed in a reasonable
    # safe place, under <code>Rails.root/tmp</code> if Rails is defined
    # otherwise under <code>Dir.tmpdir</code>.  (More details: within that
    # directory, the root directory is disambiguated by #provider and
    # #location, so that multiple Defog::Proxy instances can be
    # created without collision.)
    #
    # The upshot is that if you have no special constraints you don't need
    # to worry about it.  But if you do care, you can specify the option:
    #   :proxy_root => "/root/for/this/proxy/files"
    #
    def initialize(opts={})
      opts = opts.keyword_args(:provider => :required, :proxy_root => :optional, :OTHERS => :optional)

      @proxy_root = Pathname.new(opts.delete(:proxy_root)) if opts.proxy_root

      @fog_wrapper = FogWrapper.connect(opts)

      @proxy_root ||= case
                      when defined?(Rails) then Rails.root + "tmp"
                      else Pathname.new(Dir.tmpdir)
                      end + "defog" + provider.to_s + location

    end

    # Returns the provider for this proxy.  I.e., <code>:local</code> or
    # <code>:AWS</code>
    def provider
      @fog_wrapper.provider
    end

    # Returns a 'location' handle to use in the default proxy root path,
    # to disambiguate it from other proxies with the same provider.  For
    # :AWS it's the bucket name, for :Local it's derived from the local
    # root path.
    def location
      @fog_wrapper.location
    end

    # Returns the underlying Fog::Storage object for the cloud connection
    def fog_connection
      @fog_wrapper.fog_connection
    end
    
    # Returns the Fog directory object for the root of the cloud files
    def fog_directory
      @fog_wrapper.fog_directory
    end

    # Proxy a remote cloud file.  Returns a Defog::Handle object that
    # represents the file. 
    #
    # If a <code>mode</code> is specified given opens a proxy file via
    # Defog::Handle#open (passing it the mode and other options and
    # optional block), returning instead the Defog::File object.
    #
    # Thus 
    #    proxy.file("key", mode, options, &block)
    # is shorthand for
    #    proxy.file("key").open(mode, options, &block)
    #
    def file(key, mode=nil, opts={}, &block)
      handle = Handle.new(self, key)
      case
      when mode then handle.open(mode, opts, &block) if mode
      when block then block.call(handle)
      else handle
      end
    end

  end
end
