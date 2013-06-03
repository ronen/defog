require 'spec_helper'

shared_examples "a handle" do |proxyargs|

  before(:all) do
    @proxy = Defog::Proxy.new(proxyargs)
  end

  before(:each) do
    @handle = @proxy.file(key)
  end

  it "should have a nice to_s" do
    @handle.to_s.should include key
  end

  context "proxy path" do
    it "should start with proxy root" do
      @handle.proxy_path.to_s.should start_with(@proxy.proxy_root.to_s)
    end

    it "should end with key" do
      @handle.proxy_path.to_s.should end_with(key)
    end

    it "should include prefix" do
      prefix = "IAmAPrefix"
      Defog::Proxy.new(proxyargs.merge(:prefix => prefix)).file(key).proxy_path.to_s.should include(prefix.to_s)
    end
  end

  context "if remote cloud file exists" do

    before(:each) do
      create_remote("i exist")
    end

    it "should report exist? true" do
      @handle.should be_exist
    end

    it "should return md5 hash" do
      @handle.md5_hash.should == Digest::MD5.hexdigest("i exist")
    end
  end

  context "if remote cloud file does not exist" do
    it "should report exist? false" do
      @handle.should_not be_exist
    end

    it "should return nil md5 hash" do
      @handle.md5_hash.should be_nil
    end
  end

  { :size => :content_length,
    :last_modified => :last_modified,
    :delete => :destroy }.each do |method, fog_method|

    it "should delegate #{method.inspect} to the fog model #{fog_method.inspect} if the remote file exists" do
      create_remote("delegate me")
      @handle.fog_model.class.any_instance.should_receive(fog_method).and_return { "dummy" }
      @handle.send(method).should == "dummy"
    end

    it "should return nil from #{method} if the remote file does not exist" do
      @handle.send(method).should be_nil
    end

  end

  it "should delete a remote cloud file" do
    create_remote("delete me")
    remote_exist?.should be_true
    @handle.delete
    remote_exist?.should be_false
  end

  it "should return a URL to a file" do
    create_remote("reach out to me")
    @handle.url.should be_a String
  end

  it "should open a file" do
    Defog::File.should_receive(:open).with(hash_including(:handle => @handle, :mode => "w"))
    @handle.open("w")
  end

  it "should return a Fog model" do
    create_remote("foggy")
    @handle.fog_model.body.should == "foggy"
  end

  it "should update when file changes" do
    create_remote("abc")
    @proxy.file(key).size.should == 3
    @proxy.file(key).open("w") do |f|
      f.write("defghij")
    end
    @proxy.file(key).size.should == 7
  end


end

describe Defog::Handle do

  context "Local" do
    before(:all) do
      Fog.unmock!
    end

    args = {:provider => :local, :local_root => LOCAL_CLOUD_PATH}

    it_should_behave_like "a handle", args

    it "should return a file:// URL" do
      @proxy = Defog::Proxy.new(args)
      @proxy.file(key).url.should == "file://" + (LOCAL_CLOUD_PATH + key).to_s
    end

    context "with a rails app" do

      it "should return a path relative to public if in public" do
        with_rails_defined do
          @proxy = Defog::Proxy.new(:provider => :local, :local_root => Rails.root + "public/defog")
          @proxy.file(key).url.should == "/defog/#{key}"
        end
      end

      it "should return a file:// path if not in public" do
        with_rails_defined do
          @proxy = Defog::Proxy.new(args)
          @proxy.file(key).url.should == "file://" + (LOCAL_CLOUD_PATH + key).to_s
        end
      end
    end

  end

  context "AWS" do
    before(:all) do
      Fog.mock!
    end

    args = {:provider => :AWS, :aws_access_key_id => "dummyid", :aws_secret_access_key => "dummysecret", :region => "eu-west-1", :bucket => "tester"}
    it_should_behave_like "a handle", args

    it "should pass url query options to fog" do
      @proxy = Defog::Proxy.new(args)

      create_remote("reach out to me")
      t = Time.now + 10*60
      #Fog::Storage::AWS::File.any_instance.should_receive(:url).with(t, "response-content-disposition" => "attachment")
      url = @proxy.file(key).url(:expiry => t, :query => {"response-content-disposition" => "attachment"})
      url.should include "response-content-disposition=attachment"
    end


  end

end
