require "fastandand"

module Defog
  # Create a Defog::Handle proxy instance via Defog::Proxy#file, such as
  #
  #    defog = Defog::Proxy.new(:provider => :AWS, :aws_access_key_id => access_key, ...)
  #
  #    handle = defog.file("key/to/my/file")
  #
  # or
  #
  #    defog.file("key/to/my/file") do |handle|
  #       # ... access the proxy handle ...
  #    end
  #
  # The #proxy_path attribute method returns a <code>Pathname</code>
  # giving the local proxy file location.  Querying the attribute does
  # <i>not</i> upload, download, synchronize, or otherwise interact with
  # the cloud or local proxy file in any way -- it just returns a constructed
  # Pathname.  The <code>proxy_path</code> is a deterministic function of the
  # cloud key and Defog::Proxy#proxy_root, so you can rely on it not
  # changing between independent accesses to a cloud file.
  #
  class Handle

    attr_reader :key
    attr_reader :proxy #:nodoc:

    # Pathname where proxy file is, was, or will be located.
    attr_reader :proxy_path

    def initialize(proxy, key) #:nodoc:
      @proxy = proxy
      @key = key
      @proxy_path = Pathname.new("#{@proxy.proxy_root}/#{@proxy.prefix}#{@key}").expand_path
    end

    def to_s
      "<#{self.class}: key=#{key}>"
    end

    # Returns true if the remote cloud file exists
    def exist?
      !!fog_model
    end

    # Deletes the remote cloud file if it exists
    def delete
      fog_model and @proxy.fog_wrapper.fog_delete(@key)
    end

    # Returns the size of the remote cloud file, or nil if it doesn't exist
    def size
      fog_model.andand.content_length
    end

    # Returns the modification date of the remote cloud file, or nil if it
    # doesn't exist
    def last_modified
      fog_model.andand.last_modified
    end

    # Returns the MD5 hash digest of the remote cloud file, or nil if it
    # doesn't exist
    #
    def md5_hash
      return @proxy.fog_wrapper.get_md5(@key) if exist?
    end

    # Returns a URL to access the remote cloud file.  The options are
    # storage-specific.
    #
    # For :AWS files, the option
    #    :expiry => time
    # is required and specifies the expiration of time-limited URLS when
    # using :AWS.  The default is <code>Time.now + 10.minutes</code>.
    # The option
    #    :query => { ... }
    # is optional and is passed directly to fog.  Example usage might be
    #    :query => {'response-content-disposition' => 'attachment'}
    #
    # For :local cloud files, all options are ignored.  If Rails is defined
    # and the file is in Rails app's public directory, returns a path
    # relative to the public directory.  Otherwise returns a
    # <code>"file://"</code> URL
    def url(opts={})
      opts = opts.keyword_args(:expiry => Time.now + 10*60, :query => :optional)
      @proxy.fog_wrapper.url(@key, opts)
    end

    # Returns the underlying Fog::Model, should you need it for something.
    # Returns nil if the model doesn't exist.
    #
    # If Defog::Proxy.new was passed a :prefix, the Fog::Model key and
    # Defog::Handle key are related by:
    #   handle.fog_model.key == defog.prefix + handle.key
    def fog_model
      @proxy.fog_wrapper.fog_head(@key)
    end

    # Returns a Defog::File object, which is a specialization of ::File.
    #
    # <code>mode</code> can be the usual "r", "r+", "w", "w+", "a", or "a+" with the
    # usual semantics.  When opened in a readable mode ("r", "r+", "w+",
    # "a+"), first caches the cloud file in the local proxy.  When opened
    # in a writeable mode ("r+", "w", "w+", "a", "a+"), arranges to upload
    # the changes back to the cloud file at close time.  The mode can be
    # suffixed with 'b' or with ':' and encoding specifiers as usual.
    #
    # Like ::File.open, if called with a block yields the file object to
    # the block and ensures the file will be closed when leaving the block.
    #
    # Normally the proxy file gets deleted upon close (after synchronized
    # as needed) rather than persisted, although the default behavior can
    # be controlled by Defog::Proxy.new.  To specify persistence behavior
    # on a per-file basis, use
    #    :persist => true-or-false
    # See File#close for more details.
    #
    # If you are managing your cache size, when opening a proxy for writing
    # you may want to provide a hint as to the expected size of the data:
    #    :size_hint => 500.kilobytes
    # See README for more details.
    #
    # Normally upon close of a writeable proxy file, the synchronization
    # happens synchronously and the close will wait, althrough the behavior
    # can be controlled by Defog::Proxy.new.  To specify synchronization
    # behavior on a per-file basis, use
    #    :synchronize => true-or-false-or-async
    # See File#close for more details.
    #
    def open(mode, opts={}, &block)
      opts = opts.keyword_args(:persist => @proxy.persist, :synchronize => @proxy.synchronize, :size_hint => :optional)
      File.open(opts.merge(:handle => self, :mode => mode), &block)
    end

  end
end
