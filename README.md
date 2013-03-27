# defog

[<img
src="https://secure.travis-ci.org/ronen/defog.png"/>](http://travis-ci.org/ron
en/defog) [<img src="https://gemnasium.com/ronen/defog.png" alt="Dependency
Status" />](https://gemnasium.com/ronen/defog)

Defog wraps the [fog](https://rubygems.org/gems/fog) gem (specifically,
[Fog::Storage](http://fog.io/1.3.1/storage/)), providing access to files
stored in the cloud via proxy files on the local file system. A proxy file can
be
*   Read-only:  A local cached copy of a cloud file.
*   Write-only:  A local file that will be uploaded to the cloud.
*   Read-Write:  A local file that mirrors a cloud file, propogating changes
    back to the cloud.


Defog thus lets you use ordinary programmatic tools to access and manipulate
your cloud data.  Thanks to the magic of [fog](https://rubygems.org/gems/fog)
it works across cloud providers, and it also works with the local file system
as a "provider" so that you can, e.g. use the local file system for
development and the cloud for production.

Defog also provides a few simple remote-file management methods to minimize
the need to dig down into the Fog layer; but full access to the underlying fog
objects is available should it be needed.

## Usage Summary

Full Rdoc is available at http://rubydoc.info/gems/defog

### Create proxy connection

Connect to the remote storage by creating a `Defog::Proxy` object, which
proxies files in a specific remote location, e.g.:

    defog = Defog::Proxy.new(:provider => :AWS,
                             :aws_access_key_id => "yourid",
                             :aws_secret_access_key => "yoursecret",
                             :region => "optional-s3-region",
                             :bucket => "s3-bucket-name")

    defog = Defog::Proxy.new(:provider => :Local,
                             :local_root => "/path/to/directory")

For complete options, see Defog::Proxy.new RDOC

### Proxy a file

Open a proxy to a remote file by creating a `Defog::File` object:

    file = defog.file("key/of/file", mode)
    # ... access file ...
    file.close

    defog.file("key/of/file", mode) do |file|
       # ... access file ...
    end

`mode` can be "r", "r+", "w", "w+", "a", or "a+" with the usual semantics, and
can be suffixed with "b" or with ":" and encoding as usual.

When opened in a readable mode ("r", "r+", "w+", "a+"), Defog first caches the
cloud file in the local proxy.  When opened in a writeable mode ("r+", "w",
"w+", "a", "a+"), Defog arranges to upload the changes back to the cloud file
at close time.

The `Defog::File` class inherits from `::File`.  So you can use it directly
for I/O operations, such as

    defog.file("key", "r") do |file|
       file.readlines
    end

You can also access the proxy file via its path, allowing things such as

    defog.file("image100x100.jpg", "w") do |file|
      system("convert souce.png -scale 100x100 #{file.path}")
    end

(Note that the proxy file path has the same file extension as the cloud key
string.)

Closing the file object (explicitly or implicitly at the end of the block)
synchronizes the local proxy with the remote storage if needed, and then (by
default) deletes the local proxy file.

To suppress deleting the local proxy file, use `:persist => true` (see
Persistence below).  To suppress updating the remote storage, delete the local
proxy file before closing (e.g. via `File.unlink(file.path)`) or pass
`:synchronize => false` to the `#close` method.

### Proxy handle

Calling Defog::Proxy#file without a mode returns a Defog::Handle object that
supports cloud file query and manipulation:

    handle = defog.file("key")
    handle.exist?        # => true if the cloud file exists
    handle.delete        # deletes the cloud file
    handle.size          # => size of the cloud file
    handle.last_modified # => modification date of the cloud file

In fact, `defog.file("key", mode, options, &block)` is really just shorthand
for

    defog.file("key").open(mode, options, &block)

In addition, the handle allows you to look up the path where the local proxy
file will be if/when you open the proxy (but without actually doing the
proxying).

    defog.file("key").proxy_path  # => Pathname where proxy file is, was, or will be

You can also iterate through handles of all cloud files, e.g.:

    defog.each { |handle| puts handle.key }
    defog.each.select { |handle| handle.last_modified < 12.hours.ago }

### Persistence

By default, Defog will delete the local proxy when closing a file. However, it
is possible to keep the local proxy file so that it if the remote is accessed
again the data will not need to be transferred again. (This is true even
between executions of the program: a Defog::Proxy instance can start with
proxy files already in place, and it will use them.)

Persistence can be enabled by default for the Defog::Proxy instance via:

    defog = Defog::Proxy.new(:provider => ..., :persist => true)

And/or persistence can be overridden on a per-file basis at proxy open time:

    file = defog.file("key/of/file", mode, :persist => true)

or at proxy close time:

    file.close(:persist => true)

When opening a file whose local proxy has been persisted, Defog checks to see
if the local proxy is out of date and if so replaces it (via MD5 digests).

## Local proxy file cache

For basic usage, you don't need to worry about the cache, the default settings
work fine.  But if you will be persisting proxy files you may want to manage
the cache more carefully.

### Cache location

The cache for a given Defog::Proxy is rooted at a directory on the local file
system.  You can set and query the root via

    defog = Defog::Proxy.new(:provider => ..., :proxy_root => "/my/chosen/root")
    defog.proxy_root    # => returns a Pathname

If you don't specify a root, Defog uses one of two defaults:

    {Rails.root}/tmp/defog/{provider}-{location}  # if Rails is defined
    {Dir.tmpdir}/defog/{provider}-{location}      # if Rails is not defined

In these, `location` disambiguates between Defog::Proxy instances. For :AWS
it's the bucket name and for :local it's the `local_root` directory path with
slashes replaced with dashes.

[Why cache local files, you ask?  Why not bypass this whole cache thing if
using :local?  Well, the motivation for supporting :local is to use it in
development and use :AWS in production.  So, to more faithfully mimic
production behavior, :local mode goes through the same code path and same
caching mechanism.]

Within the cache, indvidiual proxy files are located by treating the key as a
path relative to the proxy root (with slashes in the key indicating
subdirectories in the path).

### Cache size management

Defog can perform simple size management of the local proxy file cache.  This
is of course useful mostly when persisting files.

You can specify a maximum cache size via:

    defog = Defog::Proxy.new(:provider => ..., :max_cache_size => size-in-bytes)

If a maximum size is set, then before downloading data to create a proxy,
Defog will check the space available and delete persisted proxy files as
needed in LRU order.  Does not delete files for proxies that are currently
open. If this would not free up enough space (because of open proxies or just
because the remote is larger than the cache), raises Defog::Error::CacheFull
and doesn't actually delete anything.

For writeable proxes, of course Defog doesn't know in advance the size of the
data you will write into proxy file.  As a crude estimate, if the remote file
already exists, Defog will reserve the same amount of space. Instead, you can
tell Defog the expected size via:

    defog.file("key", "w", :size_hint => size-in-bytes)

You can also manage the cache manually, by explicitly deleting an individual
persisted proxy files, such as via:

    defog.file("key").proxy_path.unlink

And it's fair game to delete proxy files outside of Defog, such as via a cron
job.  Of course in these cases it's up to you to make sure not to
unintentionally delete a proxy file that's currently open.

## Accessing Fog

You can access the underlying fog objects as needed:

    defog = Defog::Proxy.new(:provider => ...)

    defog.fog_connection         # => the Fog::Storage object
    defog.fog_directory          # => the fog directory that contains the files being proxied
    defog.file("key").fog_model  # => the fog model for the cloud file

## Installation

Gemfile:
    gem 'defog'

## Compatibility

Defog is currently known to work on:

*   Ruby:  MRI 1.9.2, MRI 1.9.3
*   Fog Storage: :local, :AWS


The above storage providers are what the author uses.  Please fork and add
others!  (There's just a very small amount of provider-specific code in one
file, https://github.com/ronen/defog/blob/master/lib/defog/fog_wrapper.rb,
plus appropriate rspec examples.)

## History

Release Notes:

*   0.7.2 - Bug fix: don't fail when clearing cache if another process clears it first
*   0.7.1 - Add key info to message if there's an exception when getting file
*   0.7.0 - Add :query option to Handle#url
*   0.6.1 - Bug fix (caching)
*   0.6.0 - Add logging


## Copyright

Released under the MIT License.  See LICENSE for details.
