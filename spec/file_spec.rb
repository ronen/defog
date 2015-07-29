require 'spec_helper'

shared_examples "get proxy" do

  it "should create proxy if remote exists" do
    create_remote("hello")
    should_log /Download/
    file = @proxy.file(key, @mode)
    expect(File.exist?(file.path)).to be_true
    file.close
  end

  it "should raise error if remote doesn't exist" do
    expect { @proxy.file("nonesuch", @mode) }.to raise_error(Defog::Error::NoCloudFile)
  end

  it "should overwrite existing proxy if it's not valid " do
    create_remote("hello")
    create_proxy("goodbye")
    expect(proxy_path.read).to eq("goodbye")
    should_log /Download/
    @proxy.file(key, @mode)
    expect(proxy_path.read).to eq("hello")
  end

  it "should use existing proxy if it's valid" do
    create_remote("hello")
    create_proxy("hello")
    handle = @proxy.file(key)
    expect(handle.proxy_path).not_to receive(:open).with(/^w/)
    should_not_log /Download/
    handle.open(@mode)
  end

  it "should include key info in exception messages" do
    create_remote("error me")
    expect_any_instance_of(File).to receive(:write) { raise Encoding::UndefinedConversionError, "dummy" }
    expect {
      @proxy.file(key, "r")
    }.to raise_error Encoding::UndefinedConversionError, /#{key}/
  end
end

shared_examples "read" do
  it "should correctly read" do
    create_remote("read me")
    @proxy.file(key, @mode) do |file|
      file.rewind
      expect(file.read).to eq("read me")
    end
  end

  it "should pass 'b' mode through" do
    create_remote("binary me")
    @proxy.file(key, "#{@mode}b") do |file|
      expect(file.external_encoding.name).to eq("ASCII-8BIT")
    end
  end

  it "should pass encodings through" do
    create_remote("encode me")
    @proxy.file(key, "#{@mode}:EUC-JP:UTF-8") do |file|
      expect(file.external_encoding.name).to eq("EUC-JP")
      expect(file.internal_encoding.name).to eq("UTF-8")
    end
  end

end

shared_examples "read after write" do
  it "should correctly read after write" do
    @proxy.file(key, @mode) do |file|
      file.write "read me"
      file.rewind
      expect(file.read).to eq("read me")
    end
  end
end

shared_examples "write" do
  it "should correctly write" do
    create_remote("dummy")
    @proxy.file(key, @mode, :persist => true) do |file|
      file.write "write me"
    end
    expect(proxy_path.read).to match(/write me$/)
  end
end

shared_examples "append" do
  it "should correctly append" do
    create_remote("hello")
    @proxy.file(key, @mode, :persist => true) do |file|
      file.write "goodbye"
      should_log /Upload/
    end
    expect(proxy_path.read).to eq("hellogoodbye")
  end
end

shared_examples "create" do

  it "should create remote" do
    should_log /Upload/
    file = @proxy.file(key, @mode)
    create_proxy("upload me")
    file.close
    expect(remote_body).to eq("upload me")
  end

  it "should not create remote if proxy is deleted" do
    should_not_log /Upload/
    @proxy.file(key, @mode) do |file|
      file.write("ignore me")
      proxy_path.unlink
    end
    expect {remote_body}.to raise_error
  end

  it "should not create remote if :synchronize => false" do
    should_not_log /Upload/
    file = @proxy.file(key, @mode)
    create_proxy("ignore me")
    file.close(:synchronize => false)
    expect {remote_body}.to raise_error
  end

  it "should create remote asynchronously if :synchronize => async" do
    should_log /Upload/
    file = @proxy.file(key, @mode)
    create_proxy("upload me in thread")
    expect(Thread).to receive(:new) { |&block|
      expect {remote_body}.to raise_error
      block.call
    }
    file.close(:synchronize => :async)
    expect(remote_body).to eq("upload me in thread")
  end

end

shared_examples "update" do

  it "should overwrite remote" do
    create_remote("overwrite me")
    expect(remote_body).to eq("overwrite me")
    file = @proxy.file(key, @mode)
    create_proxy("upload me")
    should_log /Upload/
    file.close
    expect(remote_body).to eq("upload me")
  end

  it "should overwrite remote asynchronously if :synchronize => :async" do
    create_remote("overwrite me")
    file = @proxy.file(key, @mode)
    create_proxy("upload me")
    expect(Thread).to receive(:new) { |&block|
      expect(remote_body).to eq("overwrite me")
      block.call
    }
    should_log /Upload/
    file.close(:synchronize => :async)
    expect(remote_body).to eq("upload me")
  end

  it "should not overwrite remote if proxy is deleted" do
    should_not_log /Upload/
    create_remote("keep me")
    @proxy.file(key, @mode) do |file|
      file.write("ignore me")
      proxy_path.unlink
    end
    expect(remote_body).to eq("keep me")
  end

  it "should not overwrite remote if :synchronize => false" do
    should_not_log /Upload/
    create_remote("keep me")
    file = @proxy.file(key, @mode)
    create_proxy("ignore me")
    file.close(:synchronize => false)
    expect(remote_body).to eq("keep me")
  end

end

shared_examples "persistence" do
  it "should delete proxy on close" do
    create_remote("whatever")
    file = @proxy.file(key, @mode)
    expect(proxy_path).to be_exist
    file.close
    expect(proxy_path).not_to be_exist
  end

  it "should delete proxy on close (block form)" do
    create_remote("whatever")
    @proxy.file(key, @mode) do |file|
      expect(proxy_path).to be_exist
    end
    expect(proxy_path).not_to be_exist
  end

  it "should not delete proxy if persisting" do
    create_remote("whatever")
    @proxy.file(key, @mode, :persist => true) do |file|
      expect(proxy_path).to be_exist
    end
    expect(proxy_path).to be_exist
  end

  it "close should override persist true" do
    create_remote("whatever")
    file = @proxy.file(key, @mode)
    expect(proxy_path).to be_exist
    file.close(:persist => true)
    expect(proxy_path).to be_exist
  end

  it "close should override persist false" do
    create_remote("whatever")
    file = @proxy.file(key, @mode, :persist => true)
    expect(proxy_path).to be_exist
    file.close(:persist => false)
    expect(proxy_path).not_to be_exist
  end

end

class MockLogger
  def info(arg)
  end
end

shared_examples "a proxy file" do |proxyargs|

  before(:all) do
    @proxy = Defog::Proxy.new(proxyargs)
    @proxy.logger = MockLogger.new
  end

  %W[r r+ w w+ a a+].each do |mode|

    context "mode #{mode.inspect}" do
      before(:each) do 
        @mode = mode
      end
      it_should_behave_like "get proxy" if mode =~ %r{[ra]}
      it_should_behave_like "read" if mode == "r" or mode == "a+"
      it_should_behave_like "write" if mode =~ %r{[wa+]}
      it_should_behave_like "read after write" if mode == "w+"
      it_should_behave_like "create" if mode =~ %r{w}
      it_should_behave_like "append" if mode =~ %r{a}
      it_should_behave_like "update" if mode =~ %r{[wa+]}
      it_should_behave_like "persistence"
    end
  end

  it "should raise error on bad mode" do
    expect { @proxy.file(key, "xyz") }.to raise_error(ArgumentError)
  end

  it "should have a nice to_s" do
    @proxy.file(key, "w") {|f|
      expect(f.to_s).to include f.path
    }
  end


end

describe "Defog::Proxy::File" do

  context "Local" do

    before(:all) do
      Fog.unmock!
    end

    args = {:provider => :local, :local_root => LOCAL_CLOUD_PATH, :proxy_root => PROXY_BASE_PATH + "local" }

    it_should_behave_like "a proxy file", args

  end

  context "AWS" do

    before(:all) do
      Fog.mock!
    end

    args = {:provider => :AWS, :aws_access_key_id => "dummyid", :aws_secret_access_key => "dummysecret", :region => "eu-west-1", :bucket => "tester", :proxy_root => PROXY_BASE_PATH + "AWS"}

    it_should_behave_like "a proxy file", args

  end



end
