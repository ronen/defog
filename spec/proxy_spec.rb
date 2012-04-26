require 'spec_helper'

shared_examples "a proxy" do |args|

  it "should default proxy root to tmpdir/defog" do
    proxy = Defog::Proxy.new(args)
    proxy.proxy_root.should == Pathname.new(Dir.tmpdir) + "defog" + proxy.provider.to_s + proxy.location
  end

  it "should default proxy root to Rails.root" do
    with_rails_defined do
      proxy = Defog::Proxy.new(args)
      proxy.proxy_root.should == Rails.root + "defog" + proxy.provider.to_s + proxy.location
    end
  end

  it "should accept proxy root parameter" do
    path = Pathname.new("/a/random/path")
    proxy = Defog::Proxy.new(args.merge(:proxy_root => path))
    proxy.proxy_root.should == path
  end

  context do
    before(:each) do
      @proxy = Defog::Proxy.new(args)
    end

    it "file should return a handle" do
      handle = @proxy.file(key)
      handle.proxy.should == @proxy
      handle.key.should == key
    end

    it "file should yield a handle" do
      ret = @proxy.file(key) do |handle|
        handle.proxy.should == @proxy
        handle.key.should == key
        123
      end
      ret.should == 123
    end

    it "should forward file open to handle" do
      Defog::Handle.should_receive(:new).with(@proxy, key).and_return { mock('Handle').tap { |handle|
        handle.should_receive(:open).with("r+", :persist => true)
      } }
      @proxy.file(key, "r+", :persist => true)
    end

    it "should return fog storage" do
      @proxy.fog_connection.should == @proxy.fog_directory.connection
    end

    it "should return fog directory" do
      create_remote("hello")
      @proxy.fog_directory.files.get(key).body.should == "hello"
    end
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
      Defog::Proxy.new(args).location.should == LOCAL_CLOUD_PATH.to_s.gsub(%r{/},"_")
    end

  end

  context "AWS" do
    before(:all) do
      Fog.mock!
    end

    args = {:provider => :AWS, :aws_access_key_id => "dummyid", :aws_secret_access_key => "dummysecret", :region => "eu-west-1", :bucket => "tester"}
    it_should_behave_like "a proxy", args

    it "should use the bucket name as the location" do
      Defog::Proxy.new(args).location.should == args[:bucket]
    end
  end

  it "should raise error on bad provider" do
    expect { Defog::Proxy.new(:provider => :nonesuch) }.should raise_error(ArgumentError)
  end

end
