require 'spec_helper'

shared_examples "a handle" do |proxyargs|

  before(:all) do
    @proxy = Defog::Proxy.new(proxyargs)
  end

  before(:each) do
    @handle = @proxy.file(key)
  end

  it "should have a nice to_s" do
    expect(@handle.to_s).to include key
  end

  context "proxy path" do
    it "should start with proxy root" do
      expect(@handle.proxy_path.to_s).to start_with(@proxy.proxy_root.to_s)
    end

    it "should end with key" do
      expect(@handle.proxy_path.to_s).to end_with(key)
    end

    it "should include prefix" do
      prefix = "IAmAPrefix"
      expect(Defog::Proxy.new(proxyargs.merge(:prefix => prefix)).file(key).proxy_path.to_s).to include(prefix.to_s)
    end
  end

  context "if remote cloud file exists" do

    before(:each) do
      create_remote("i exist")
    end

    it "should report exist? true" do
      expect(@handle).to be_exist
    end

    it "should return md5 hash" do
      expect(@handle.md5_hash).to eq(Digest::MD5.hexdigest("i exist"))
    end
  end

  context "if remote cloud file does not exist" do
    it "should report exist? false" do
      expect(@handle).not_to be_exist
    end

    it "should return nil md5 hash" do
      expect(@handle.md5_hash).to be_nil
    end
  end

  { :size => :content_length,
    :last_modified => :last_modified,
    :delete => :destroy }.each do |method, fog_method|

    it "should delegate #{method.inspect} to the fog model #{fog_method.inspect} if the remote file exists" do
      create_remote("delegate me")
      expect_any_instance_of(@handle.fog_model.class).to receive(fog_method) { "dummy" }
      expect(@handle.send(method)).to eq("dummy")
    end

    it "should return nil from #{method} if the remote file does not exist" do
      expect(@handle.send(method)).to be_nil
    end

  end

  it "should delete a remote cloud file" do
    create_remote("delete me")
    expect(remote_exist?).to be_truthy
    @handle.delete
    expect(remote_exist?).to be_falsey
  end

  it "should return a URL to a file" do
    create_remote("reach out to me")
    expect(@handle.url).to be_a String
  end

  it "should open a file" do
    expect(Defog::File).to receive(:open).with(hash_including(:handle => @handle, :mode => "w"))
    @handle.open("w")
  end

  it "should return a Fog model" do
    create_remote("foggy")
    expect(@handle.fog_model.body).to eq("foggy")
  end

  it "should update when file changes" do
    create_remote("abc")
    expect(@proxy.file(key).size).to eq(3)
    @proxy.file(key).open("w") do |f|
      f.write("defghij")
    end
    expect(@proxy.file(key).size).to eq(7)
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
      expect(@proxy.file(key).url).to eq("file://" + (LOCAL_CLOUD_PATH + key).to_s)
    end

    context "with a rails app" do

      it "should return a path relative to public if in public" do
        with_rails_defined do
          @proxy = Defog::Proxy.new(:provider => :local, :local_root => Rails.root + "public/defog")
          expect(@proxy.file(key).url).to eq("/defog/#{key}")
        end
      end

      it "should return a file:// path if not in public" do
        with_rails_defined do
          @proxy = Defog::Proxy.new(args)
          expect(@proxy.file(key).url).to eq("file://" + (LOCAL_CLOUD_PATH + key).to_s)
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
      expect(url).to include "response-content-disposition=attachment"
    end


  end

end
