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
                      when defined?(Rails) then Rails.root
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

    # Proxy a remote cloud file.  Returns a Defog::File object, which is a
    # specialization of ::File. 
    #
    # <code>key</code> is the cloud storage key for the file.
    #
    # <code>mode</code> can be "r", "r+", "w", "w+", "a", or "a+" with the
    # usual semantics.
    #
    # Like ::File.open, if called with a block yields the file object to
    # the block and ensures the file will be closed when leaving the block.
    #
    # Normally the proxy file is synchronized and then deleted upon close.
    # Pass
    #    :persist => true
    # to maintain the file after closing.   See File#close for more
    # details.
    #
    def file(key, mode, opts={}, &block)
      opts = opts.keyword_args(:persist)
      File.get(opts.merge(:proxy => self, :key => key, :mode => mode), &block)
    end

  end
end
