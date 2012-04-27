module Defog
  # Create a Defog::File proxy instance via Defog::Handle#open or via the
  # shortcut from Defog::Proxy#file, such as
  #
  #    defog = Defog::Proxy.new(:provider => :AWS, :aws_access_key_id => access_key, ...)
  #
  #    defog.file("key/to/my/file", "w") do |file|
  #       # ... access the proxy file ...
  #    end
  #
  # or
  #
  #    file = defog.file("key/to/my/file", "w")
  #    # ... access the proxy file ...
  #    file.close
  #  
  # Defog::File inherits from ::File, so you can act on the proxy file using
  # ordinary IO methods, such as
  #
  #    defog.file("key", "r") do |file|
  #       file.readlines
  #    end
  #
  # You can also access the proxy file via its path, allowing things such
  # as
  #    defog.file("image100x100.jpg", "w") do |file|
  #       system("convert souce.png -scale 100x100 #{file.path}")
  #    end
  # 
  # (Note that the proxy file path has the same file extension as the cloud key string.)
  #
  # Upon closing the proxy file, in normal use the cloud storage gets
  # synchronized if needed and the proxy deleted.  To prevent deletion, you
  # can use:
  #    defog.file("key", "r", :persist => true)
  # See File#close for more details.
  #
  # If you are managing your cache size, when opening a proxy for writing you may want to provide a hint as
  # to the expected size of the data:
  #    defog.file("key", "w", :size_hint => 500.kilobytes)
  # See README for more details.
  #
  class File < ::File

    def initialize(opts={}, &block) #:nodoc:
      opts = opts.keyword_args(:handle => :required, :mode => :required, :persist => :optional, :size_hint => :optional)
      @handle = opts.handle
      @persist = opts.persist

      key = @handle.key
      proxy_path = @handle.proxy_path
      proxy_path.dirname.mkpath
      case opts.mode
      when "r"
        download = true
        @upload = false
        cache_size = @handle.size
      when "w", "w+"
        download = false
        @upload = true
        cache_size = opts.size_hint || @handle.size
      when "r+", "a", "a+"
        download = true
        @upload = true
        cache_size = [opts.size_hint, @handle.size].compact.max
      else
        raise ArgumentError, "Invalid mode #{opts.mode.inspect}"
      end

      @handle.proxy.manage_cache(cache_size, proxy_path)
      @handle.proxy.reserve_proxy_path(proxy_path)
      download_proxy if download
      super(proxy_path, opts.mode, &block)
    end

    def download_proxy
      @handle.proxy.fog_wrapper.get_file(@handle.key, @handle.proxy_path)
    end

    def upload_proxy
      @handle.proxy.fog_wrapper.put_file(@handle.key, @handle.proxy_path) 
    end


    # Closes the proxy file and synchronizes the cloud storage (if it was
    # opened as writeable) then deletes the proxy file.
    #
    # Synchronization can be suppressed by passing the option
    #    :synchronize => false
    # Synchronization will also be implicitly suppressed if the proxy file
    # was deleted before this call, e.g., via <code>::File.unlink(file.path)</code>.
    #
    #
    # Whether the proxy file gets deleted vs persisted after the close can
    # be set by passing the option
    #    :persist => true or false
    # (This will override the setting of <code>:persist</code> passed to Proxy#file)
    #
    def close(opts={})
      opts = opts.keyword_args(:persist => @persist, :synchronize => true)
      super()
      proxy_path = @handle.proxy_path
      if proxy_path.exist?
        upload_proxy if @upload and opts.synchronize
        proxy_path.unlink unless opts.persist
      end
      @handle.proxy.release_proxy_path(proxy_path)
    end
  end
end
