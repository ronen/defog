require 'spec_helper'

shared_examples "a proxy" do |args|

  it "should default proxy root to tmpdir/defog" do
    proxy = Defog::Proxy.new(args)
    proxy.proxy_root.should == Pathname.new(Dir.tmpdir) + "defog" + proxy.provider.to_s + proxy.location
  end

  it "should default proxy root to Rails.root" do
    begin
      Kernel.const_set("Rails", Struct.new(:root).new("/dummy/rails/app/"))
      proxy = Defog::Proxy.new(args)
      proxy.proxy_root.should == Rails.root + "defog" + proxy.provider.to_s + proxy.location
    ensure
      Kernel.send :remove_const, "Rails"
    end
  end

  it "should accept proxy root parameter" do
    path = Pathname.new("/a/random/path")
    proxy = Defog::Proxy.new(args.merge(:proxy_root => path))
    proxy.proxy_root.should == path
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
