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
      opts = opts.keyword_args(:handle => :required,
                               :mode => :required,
                               :persist => :optional,
                               :synchronize => { :valid => [:async, true, false], :default => true},
                               :size_hint => :optional)
      @handle = opts.handle
      @persist = opts.persist
      @synchronize = opts.synchronize
      @mode = opts.mode

      key = @handle.key
      proxy_path = @handle.proxy_path
      proxy_path.dirname.mkpath
      re_encoding = /(b|:.*)$/
      @encoding = @mode.match(re_encoding).to_s
      case @mode.sub(re_encoding,'')
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
        raise ArgumentError, "Invalid mode #{@mode.inspect}"
      end

      @handle.proxy.manage_cache(cache_size, proxy_path)
      @handle.proxy.reserve_proxy_path(proxy_path)
      download_proxy if download
      super(proxy_path, @mode, &block)
    end

    def to_s
      "<#{self.class}: proxy=#{@handle.proxy_path} mode=#{@mode}>"
    end

    # Closes the proxy file and synchronizes the cloud storage (if it was
    # opened as writeable) then deletes the proxy file.
    #
    # Synchronization (i.e. upload of a proxy) can be controlled by passing the option
    #    :synchronize => :async # upload asynchronously in a separate thread
    #    :synchronize => true   # upload synchronously
    #    :synchronize => false  # don't upload
    # Synchronization will also be implicitly suppressed if the proxy file
    # was deleted before this call, e.g., via <code>::File.unlink(file.path)</code>.
    #
    # Whether the proxy file gets deleted vs persisted after the close can
    # be set by passing the option
    #    :persist => true or false
    #
    # The :persist and :synchronize values override the settings passed to
    # Handle#open, which in turn overrides the settings passed to Proxy.new
    #
    def close(opts={})
      opts = opts.keyword_args(:persist => @persist,
                               :synchronize => { :valid => [true, false, :async], :default => @synchronize })
      @persist = opts.persist
      @synchronize = opts.synchronize
      super()
      if @handle.proxy_path.exist?
        if @upload and @synchronize == :async
          Thread.new { wrap_proxy }
        else
          wrap_proxy
        end
      end
      @handle.proxy.release_proxy_path(@handle.proxy_path)
    end

    def download_proxy #:nodoc:
      @handle.proxy.fog_wrapper.get_file(@handle.key, @handle.proxy_path, @encoding)
    end

    def upload_proxy #:nodoc:
      @handle.proxy.fog_wrapper.put_file(@handle.key, @handle.proxy_path, @encoding) 
    end

    def wrap_proxy #:nodoc:
      upload_proxy if @upload and @synchronize
      @handle.proxy_path.unlink unless @persist
    end

  end
end
