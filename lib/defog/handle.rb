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
      @proxy_path = Pathname.new("#{@proxy.proxy_root}/#{@key}").expand_path
    end

    # Returns true if the remote cloud file exists 
    def exist?
      !!fog_model
    end

    # Deletes the remote cloud file if it exists
    def delete
      fog_model.andand.destroy
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

    # Returns a URL to access the remote cloud file.
    #
    # The option
    #    :expiry => time
    # Specifies the expiration of time-limited URLS when using :AWS.  The default is
    # <code>Time.now + 10.minutes</code>.  The expiry is ignored when using :local
    #
    # For :local cloud files, if Rails is defined and the file is in the
    # Rails app's public directory, returns a site path relative to
    # the public directory.  Otherwise returns a <code>"file://"</code> URL 
    def url(opts={})
      opts = opts.keyword_args(:expiry => Time.now + 10*60)
      @proxy.fog_wrapper.url(@key, opts.expiry)
    end

    # Returns the underlying Fog::Model, should you need it for something.
    def fog_model
      @proxy.fog_wrapper.fog_head(@key)
    end

    # Returns a Defog::File object, which is a specialization of ::File. 
    #
    # <code>mode</code> can be "r", "r+", "w", "w+", "a", or "a+" with the
    # usual semantics.  When opened in a readable mode ("r", "r+", "w+",
    # "a+"), first caches the cloud file in the local proxy.  When opened
    # in a writeable mode ("r+", "w", "w+", "a", "a+"), arranges to upload
    # the changes back to the cloud file at close time.
    #
    # Like ::File.open, if called with a block yields the file object to
    # the block and ensures the file will be closed when leaving the block.
    #
    # Normally upon close the proxy file is synchronized as needed and then deleted.
    # Pass
    #    :persist => true
    # to suppress deleting the file and so maintain the file after closing.   See File#close for more
    # details.
    def open(mode, opts={}, &block)
      opts = opts.keyword_args(:persist => @proxy.persist)
      File.open(opts.merge(:handle => self, :mode => mode), &block)
    end

  end
end
