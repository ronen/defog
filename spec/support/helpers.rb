module Helpers

  def key
    # returns a key that will be different for each example, to avoid any
    # cross-example interactions
    example.metadata[:full_description].gsub(/\+/,'plus').gsub(/\W/,'-') + "/filename"
  end

  def create_remote(body)
    @proxy.fog_directory.files.create(:key => key, :body => body)
  end

  def proxy_path
    @proxy.file(key).proxy_path
  end

  def create_proxy(body)
    path = proxy_path
    path.dirname.mkpath
    path.open("w") do |f|
      f.write(body)
    end
  end

  def remote_body
    @proxy.fog_directory.files.get(key).body
  end

  def remote_exist?
    !!@proxy.fog_directory.files.head(key)
  end

  def with_rails_defined
    begin
      Kernel.const_set("Rails", Struct.new(:root).new(RAILS_ROOT_PATH))
      yield
    ensure
      Kernel.send :remove_const, "Rails"
    end
  end

end
