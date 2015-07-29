require 'spec_helper'

shared_examples "a proxy" do |args|

  context "basic features" do
    before(:each) do
      @proxy = Defog::Proxy.new(args)
    end

    it "should have a nice to_s" do
      expect(@proxy.to_s).to include @proxy.provider.to_s
      expect(@proxy.to_s).to include @proxy.location
    end

    it "file should return a handle" do
      handle = @proxy.file(key)
      expect(handle.proxy).to eq(@proxy)
      expect(handle.key).to eq(key)
    end

    it "file should yield a handle" do
      ret = @proxy.file(key) do |handle|
        expect(handle.proxy).to eq(@proxy)
        expect(handle.key).to eq(key)
        123
      end
      expect(ret).to eq(123)
    end

    it "should forward file open to handle" do
      expect(Defog::Handle).to receive(:new).with(@proxy, key) { double('Handle').tap { |handle|
        expect(handle).to receive(:open).with("r+", :persist => true)
      } }
      @proxy.file(key, "r+", :persist => true)
    end

    it "should return fog storage" do
      expect(@proxy.fog_connection).to eq(@proxy.fog_directory.service)
    end

    it "should return fog directory" do
      create_remote("hello")
      expect(@proxy.fog_directory.files.get(key).body).to eq("hello")
    end
  end

  context "settings" do
    it "should set default for :persist => true" do
      @proxy = Defog::Proxy.new(args.merge(:persist => true))
      expect(Defog::File).to receive(:open).with(hash_including :persist => true)
      @proxy.file(key, "w") do end
    end
    it "should set default for :synchronize => :async" do
      @proxy = Defog::Proxy.new(args.merge(:synchronize => :async))
      expect(Defog::File).to receive(:open).with(hash_including :synchronize => :async)
      @proxy.file(key, "w") do end
    end
  end


  context "iteration" do

    before(:each) do
      @proxy = Defog::Proxy.new(args)
      @proxy.fog_directory.files.all.each do |model| model.destroy end
      create_other_remote("i0")
      create_other_remote("i1")
      create_other_remote("i2")
    end

    it "should iterate through remotes" do
      seen = []
      @proxy.each do |handle|
        seen << handle.key
      end
      expect(seen).to match_array([other_key("i0"), other_key("i1"), other_key("i2")])
    end

    it "should return an enumerator" do
      expect(@proxy.each.map(&:key)).to match_array([other_key("i0"), other_key("i1"), other_key("i2")])
    end

  end

  context "prefix" do
    it "should return its prefix" do
      prefix = "me-first"
      @proxy = Defog::Proxy.new(args.merge(:prefix => prefix))
      expect(@proxy.prefix).to eq(prefix)
    end

    it "should use a prefix" do
      prefix = "me-first"
      @proxy = Defog::Proxy.new(args.merge(:prefix => prefix))
      @proxy.file(key, "w") { |f| f.puts "hello" }
      expect(@proxy.file(key).fog_model.key).to eq(prefix + key)
    end

    it "should iterate only matches to prefix" do
      @proxy = Defog::Proxy.new(args.merge(:prefix => "yes-"))
      @proxy.fog_directory.files.all.each do |model| model.destroy end
      create_other_remote("no-n1")
      create_other_remote("no-n2")
      create_other_remote("no-n3")
      create_other_remote("yes-y1")
      create_other_remote("yes-y2")
      create_other_remote("yes-y3")
      expect(@proxy.each.map(&:key)).to match_array([other_key("y1"), other_key("y2"), other_key("y3")])
    end

  end

  context "proxy root location" do
    it "should default proxy root to tmpdir/defog" do
      proxy = Defog::Proxy.new(args)
      expect(proxy.proxy_root).to eq(Pathname.new(Dir.tmpdir) + "defog" + "#{proxy.provider.to_s}-#{proxy.location}")
    end

    it "should default proxy root to Rails.root" do
      with_rails_defined do
        proxy = Defog::Proxy.new(args)
        expect(proxy.proxy_root).to eq(Rails.root + "tmp/defog" + "#{proxy.provider.to_s}-#{proxy.location}")
      end
    end

    it "should accept proxy root parameter" do
      path = Pathname.new("/a/random/path")
      proxy = Defog::Proxy.new(args.merge(:proxy_root => path))
      expect(proxy.proxy_root).to eq(path)
    end
  end

  context "cache management" do
    before(:each) do
      @proxy = Defog::Proxy.new(args.merge(:max_cache_size => 100, :persist => true))
      @proxy.proxy_root.rmtree if @proxy.proxy_root.exist?
      @proxy.proxy_root.mkpath
    end

    it "should fail normally when trying to proxy a file that doesn't exist" do
      expect { @proxy.file("nonesuch", "r") }.to raise_error(Defog::Error::NoCloudFile)
    end

    it "should raise an error trying to proxy a file larger than the cache" do
      create_remote("x" * 101)
      expect { @proxy.file(key, "r") }.to raise_error(Defog::Error::CacheFull)
      expect(proxy_path).not_to be_exist
    end

    it "should not count existing proxy in total" do
      create_proxy("y" * 70)
      create_remote("x" * 70)
      expect { @proxy.file(key, "r") do end }.not_to raise_error
      expect(proxy_path).to be_exist
      expect(proxy_path.read).to eq(remote_body)
    end

    it "should delete proxies to make room" do
      create_other_proxy("a", 10)
      create_other_proxy("b", 30)
      create_other_proxy("c", 40)
      create_remote("x" * 80)
      expect { @proxy.file(key, "r") do end }.not_to raise_error
      expect(proxy_path).to be_exist
      expect(other_proxy_path("a")).to be_exist
      expect(other_proxy_path("b")).not_to be_exist
      expect(other_proxy_path("c")).not_to be_exist
    end

    [0, 3, 6].each do |sizect|
      it "should not fail size check #{sizect} when proxies get deleted by another process" do
        create_other_proxy("a", 30)
        create_other_proxy("b", 30)
        create_other_proxy("c", 30)
        create_remote("x" * 9)
        z = 0
        allow_any_instance_of(Pathname).to receive(:size) { |path|
          raise Errno::ENOENT if z == sizect
          z += 1
          30
        }
        expect { @proxy.file(key, "r") do end }.not_to raise_error
      end
    end

    it "should not fail unlinking when proxies get deleted by another process" do
      create_other_proxy("a", 10)
      create_other_proxy("b", 30)
      create_other_proxy("c", 40)
      create_remote("x" * 80)
      allow_any_instance_of(Pathname).to receive(:unlink) { raise Errno::ENOENT }
      expect { @proxy.file(key, "r") do end }.not_to raise_error
    end

    it "should not fail atime when a proxy gets deleted by another process" do
      create_other_proxy("a", 10)
      create_other_proxy("b", 30)
      create_other_proxy("c", 40)
      create_remote("x" * 80)
      allow_any_instance_of(Pathname).to receive(:atime) {
        @raised = true and raise Errno::ENOENT unless @raised
        Time.now
      }
      expect { @proxy.file(key, "r") do end }.not_to raise_error
    end

    it "should delete proxies to make room for hinted size" do
      create_other_proxy("a", 10)
      create_other_proxy("b", 30)
      create_other_proxy("c", 40)
      expect { @proxy.file(key, "w", :size_hint => 80) do end }.not_to raise_error
      expect(proxy_path).to be_exist
      expect(other_proxy_path("a")).to be_exist
      expect(other_proxy_path("b")).not_to be_exist
      expect(other_proxy_path("c")).not_to be_exist
    end

    it "should not delete proxies that are open" do
      create_other_proxy("a", 20)
      create_other_proxy("b", 20)
      create_other_remote("R", 30)
      create_remote("x" * 30)
      @proxy.file(other_key("R"), "r") do
        @proxy.file(other_key("S"), "w") do
          create_other_proxy("S", 30)
          expect { @proxy.file(key, "r") do end }.not_to raise_error
          expect(proxy_path).to be_exist
          expect(other_proxy_path("R")).to be_exist
          expect(other_proxy_path("S")).to be_exist
          expect(other_proxy_path("a")).not_to be_exist
          expect(other_proxy_path("b")).not_to be_exist
        end
      end
    end

    it "should delete proxies that are no longer open" do
      create_other_remote("R", 60)
      create_remote("z" * 60)
      @proxy.file(other_key("R"), "r") do end
      expect(other_proxy_path("R")).to be_exist
      expect { @proxy.file(key, "r") do end }.not_to raise_error
      expect(proxy_path).to be_exist
      expect(other_proxy_path("R")).not_to be_exist
    end

    it "should not delete proxies if there wouldn't be enough space" do
      create_other_proxy("a", 20)
      create_other_proxy("b", 20)
      create_other_remote("R", 30)
      create_other_remote("S", 30)
      create_remote("z" * 50)
      @proxy.file(other_key("R"), "r") do
        @proxy.file(other_key("S"), "r") do
          expect { @proxy.file(key, "r") do end }.to raise_error(Defog::Error::CacheFull)
          expect(proxy_path).not_to be_exist
          expect(other_proxy_path("a")).to be_exist
          expect(other_proxy_path("b")).to be_exist
          expect(other_proxy_path("R")).to be_exist
          expect(other_proxy_path("S")).to be_exist
        end
      end
    end

  end

  private

  def other_key(okey)
    "#{okey}-#{key}"
  end

  def create_other_proxy(okey, size)
    path = other_proxy_path(okey)
    path.dirname.mkpath
    path.open("w") do |f|
      f.write("x" * size)
    end
  end

  def other_proxy_path(okey)
    @proxy.file(other_key(okey)).proxy_path
  end

  def create_other_remote(okey, size=10)
    @proxy.fog_directory.files.create(:key => other_key(okey), :body => "x" * size)
  end

end

describe Defog::Proxy do

  context "Local" do
    before(:all) do
      Fog.unmock!
    end

    args = {:provider => :local, :local_root => LOCAL_CLOUD_PATH}

    it_should_behave_like "a proxy", args

    it "should use the deslashed local_root as the location" do
      expect(Defog::Proxy.new(args).location).to eq(LOCAL_CLOUD_PATH.to_s.gsub(%r{/},"-"))
    end

  end

  context "AWS" do
    before(:all) do
      Fog.mock!
    end

    args = {:provider => :AWS, :aws_access_key_id => "dummyid", :aws_secret_access_key => "dummysecret", :region => "eu-west-1", :bucket => "tester"}
    it_should_behave_like "a proxy", args

    it "should use the bucket name as the location" do
      expect(Defog::Proxy.new(args).location).to eq(args[:bucket])
    end

    it "should share fog connection with same bucket" do
      proxy1 = Defog::Proxy.new(args)
      proxy2 = Defog::Proxy.new(args)
      expect(proxy1.fog_connection).to be_equal proxy2.fog_connection
    end

    it "should share fog connection with different bucket" do
      proxy1 = Defog::Proxy.new(args)
      proxy2 = Defog::Proxy.new(args.merge(:bucket => "other"))
      expect(proxy1.fog_connection).to be_equal proxy2.fog_connection
    end

    it "should not share fog connection with different connection args" do
      proxy1 = Defog::Proxy.new(args)
      proxy2 = Defog::Proxy.new(args.merge(:aws_access_key_id => "other"))
      expect(proxy1.fog_connection).not_to be_equal proxy2.fog_connection
    end

  end

  it "should raise error on bad provider" do
    expect { Defog::Proxy.new(:provider => :nonesuch) }.to raise_error(ArgumentError)
  end

end
