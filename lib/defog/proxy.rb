require "hash_keyword_args"
require "pathname"
require "set"
require "tmpdir"

module Defog
  class Proxy

    attr_reader :proxy_root
    attr_reader :persist
    attr_reader :synchronize
    attr_reader :max_cache_size

    attr_reader :fog_wrapper    # :nodoc:

    # Opens a <code>Fog</code> cloud storage connection to map to a corresponding proxy
    # directory.  Use via, e.g.,
    #
    #     defog = Defog::Proxy.new(:provider => :AWS, :aws_access_key_id => access_key, ...)
    #
    # The <code>:provider</code> and its corresponding options must be
    # specified as per <code>Fog::Storage.new</code>.  Currently, only
    # <code>:local</code> and <code>:AWS</code> are supported.  When using
    # <code>:AWS</code>, an additional option <code>:bucket</code> must be
    # specified; all files proxied by this instance must be in a single
    # bucket.  (It's OK to create multiple Defog::Proxy instances with
    # the same access info but different buckets; they will internally
    # share a single Fog::Storage isntance hence AWS connection.)
    #
    # To further restrict the remote files acted on by this proxy, you
    # can specify
    #   defog = Defog::Proxy.new(:provider => ..., :prefix => "my-prefix-string/")
    # and all keys that you pass to Defog will be prefixed with the given
    # string before being passed along to Fog.  (Notice that it's up to you to
    # have a trailing "/" in the prefix if that's what you want.)
    #
    # By default, each proxy's cache root directory is placed in a
    # reasonable safe place, under <code>Rails.root/tmp</code> if Rails is
    # defined otherwise under <code>Dir.tmpdir</code>.  (More details:
    # within that directory, the root directory is disambiguated by
    # #provider and #location, so that multiple Defog::Proxy instances can
    # be created without collision.)
    #
    # The upshot is that if you have no special constraints you don't need
    # to worry about it.  But if you do care, you can specify the option:
    #   :proxy_root => "/root/for/this/proxy/files"
    #
    # You can specify that by default local proxy files will be persisted,
    # by specifying
    #   :persist => true
    # The persistence behavior can be overriden on a per-file basis when
    # opening or closing a proxy (see Defog::Handle#open, Defog::File#close)
    #
    # You can enable cache management by specifying a max cache size in
    # bytes, e.g.
    #    :max_cache_size => 3.gigabytes
    # See the README for discussion.  [Number#gigabytes is defined in
    # Rails' ActiveSupport core extensions]
    # 
    # Normally synchronization (i.e. upload) of changes to local proxy
    # files happens synchronously on close; i.e. Defog::File#close waits
    # until the upload completes.  However, you can control synchronization
    # by specifying
    #     :synchronize => :async        # Synchronize in a separate thread, don't wait
    #     :synchronize => false         # Don't synchronize at all.  Defeats the purpose of Defog
    #     :synchronize => true          # This is the default behavior
    # The synchronization behavior can be overridden on a per-file basis
    # when opening or closing a proxy (see Defog::Handle#open,
    # Defog::File#close).  Note that this applies only to upload of changes to
    # proxy files that are opened as writeable; the download of data to
    # readable proxy files always happens synchronously.
    #
    # If you specify
    #      :logger => an-instance-of-Logger
    # (or provide a logger via #logger=), Defog will log downloads and
    # upload using Logger#info.
    def initialize(opts={})
      opts = opts.keyword_args(:provider => :required,
                               :proxy_root => :optional,
                               :persist => :optional,
                               :synchronize => {:valid => [:async, true, false], :default => true},
                               :max_cache_size => :optional,
                               :OTHERS => :optional)

      @proxy_root = Pathname.new(opts.delete(:proxy_root)) if opts.proxy_root
      @persist = opts.delete(:persist)
      @synchronize = opts.delete(:synchronize)
      @max_cache_size = opts.delete(:max_cache_size)
      @reserved_proxy_paths = Set.new

      @fog_wrapper = FogWrapper.connect(opts)

      @proxy_root ||= case
                      when defined?(Rails) then Rails.root + "tmp"
                      else Pathname.new(Dir.tmpdir)
                      end + "defog" + "#{provider}-#{location}"

    end

    def to_s
      "<#{self.class} provider=#{provider} location=#{location}>"
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

    # Returns the prefix that was passed
    def prefix
      @fog_wrapper.prefix
    end

    def logger
      @fog_wrapper.logger
    end

    def logger=(log)
      @fog_wrapper.logger= log
    end

    # Proxy a remote cloud file.  Returns or yields a Defog::Handle object that
    # represents the file. 
    #
    # If a <code>mode</code> is given, opens a proxy file via
    # Defog::Handle#open (passing it the mode and other options and
    # optional block), returning or yielding instead the Defog::File object.
    #
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

    # Iterate through the cloud storage, yielding a Defog::Handle for each
    # remote file.
    #
    # If no block is given, an enumerator is returned.
    def each(&block)
      if block_given?
        @fog_wrapper.each do |key|
          yield file(key)
        end
      else
        to_enum(:each)
      end
    end

    ###############################
    # public-but-internal methods
    #

    def reserve_proxy_path(proxy_path) #:nodoc:
      @reserved_proxy_paths << proxy_path
    end

    def release_proxy_path(proxy_path) #:nodoc:
      @reserved_proxy_paths.delete proxy_path
    end

    def manage_cache(want_size, proxy_path) #:nodoc:
      return if max_cache_size.nil?
      return if want_size.nil?
      return if want_size <= 0

      # find available space (not counting current proxy)
      available = max_cache_size
      proxy_root.find { |path|
        available -= pathTry(path, :size) if path.file? and path != proxy_path
      }
      return if available >= want_size

      space_needed = want_size - available

      # find all paths in the cache that aren't currently open (not
      # counting current proxy)
      candidates = []
      proxy_root.find { |path| candidates << path if path.file? and not @reserved_proxy_paths.include?(path) and path != proxy_path}

      # take candidates in LRU order until that would be enough space
      would_free = 0
      candidates = Set.new(candidates.sort_by(&:atime).take_while{|path| (would_free < space_needed).tap{|condition| would_free += pathTry(path, :size)}})

      # still not enough...?
      raise Error::CacheFull, "No room in cache for #{proxy_path.relative_path_from(proxy_root)}: size=#{want_size} available=#{available} can_free=#{would_free} (max_cache_size=#{max_cache_size})" if would_free < space_needed

      # LRU order may have taken more than needed, if last file was a big
      # chunk.  So take another pass, eliminating files that aren't needed.
      # Do this in reverse size order, since we want to keep big files in
      # the cache if possible since they're most expensive to replace.
      size = Hash.new { |h, path| h[path] = pathTry(path, :size) }
      candidates.sort_by{|path| size[path]}.reverse.each do |path|
        if (would_free - size[path]) > space_needed
          candidates.delete path
          would_free -= size[path]
        end
      end

      # free the remaining candidates
      candidates.each do |candidate|
        pathTry(candidate, :unlink)
      end
    end

    # try a method on a Pathname without failing if the file doesn't exist
    # (which could happen if some other process sneaks in and deletes the
    # file after we found it).
    def pathTry(path, method)
      begin
        path.send method
      rescue Errno::ENOENT
        0
      end
    end

  end
end
