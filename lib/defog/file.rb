module Defog
  # Create a Defog::File proxy instance via Defog::Proxy#file, such as
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
  # Upon closing the proxy file, in normal use the cloud storage gets synchronized and
  # the proxy deleted.  See File#close for more details.
  class File < ::File
    def self.get(opts={}, &block) #:nodoc:
      opts = opts.keyword_args(:proxy => :required, :key => :required, :mode => :required, :persist => :optional)

      proxy_path = opts[:proxy_path] = Pathname.new("#{opts.proxy.proxy_root}/#{opts.key}").expand_path
      proxy_path.dirname.mkpath

      case opts.mode
      when "r" then
        opts.proxy.fog_wrapper.get_file(opts.key, proxy_path)
      when "w", "w+" then
        opts[:upload] = true
      when "r+", "a", "a+" then
        opts.proxy.fog_wrapper.get_file(opts.key, proxy_path)
        opts[:upload] = true
      else
        raise ArgumentError, "Invalid mode #{opts.mode.inspect}"
      end

      self.open(opts, &block)
    end

    def initialize(opts={}, &block) #:nodoc:
      @defog = opts.keyword_args(:proxy => :required, :mode => :required, :key => :required, :proxy_path => :required, :upload => :optional, :persist => :optional)
      super(@defog.proxy_path, @defog.mode, &block)
    end

    # Closes the proxy file and, in the common case, synchronizes the cloud storage
    # then deletes the proxy file.
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
      opts = opts.keyword_args(:persist => @defog.persist, :synchronize => true)
      super()
      if @defog.proxy_path.exist?
        @defog.proxy.fog_wrapper.put_file(@defog.key, @defog.proxy_path) if @defog.upload and opts.synchronize
        @defog.proxy_path.unlink unless opts.persist
      end
    end
  end
end
