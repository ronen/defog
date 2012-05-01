require 'spec_helper'

shared_examples "get proxy" do

  it "should create proxy if remote exists" do
    create_remote("hello")
    should_log /download/
    file = @proxy.file(key, @mode)
    File.exist?(file.path).should be_true
    file.close
  end

  it "should raise error if remote doesn't exist" do
    expect { @proxy.file("nonesuch", @mode) }.should raise_error(Defog::Error::NoCloudFile)
  end

  it "should overwrite existing proxy if it's not valid " do
    create_remote("hello")
    create_proxy("goodbye")
    proxy_path.read.should == "goodbye"
    should_log /download/
    @proxy.file(key, @mode)
    proxy_path.read.should == "hello"
  end

  it "should use existing proxy if it's valid" do
    create_remote("hello")
    create_proxy("hello")
    handle = @proxy.file(key)
    handle.proxy_path.should_not_receive(:open).with(/^w/)
    should_not_log /download/
    handle.open(@mode)
  end
end

shared_examples "read" do
  it "should correctly read" do
    create_remote("read me")
    @proxy.file(key, @mode) do |file|
      file.rewind
      file.read.should == "read me"
    end
  end

  it "should pass 'b' mode through" do
    create_remote("binary me")
    @proxy.file(key, "#{@mode}b") do |file|
      file.external_encoding.name.should == "ASCII-8BIT"
    end
  end

  it "should pass encodings through" do
    create_remote("encode me")
    @proxy.file(key, "#{@mode}:EUC-JP:UTF-16") do |file|
      file.external_encoding.name.should == "EUC-JP"
      file.internal_encoding.name.should == "UTF-16"
    end
  end

end

shared_examples "read after write" do
  it "should correctly read after write" do
    @proxy.file(key, @mode) do |file|
      file.write "read me"
      file.rewind
      file.read.should == "read me"
    end
  end
end

shared_examples "write" do
  it "should correctly write" do
    create_remote("dummy")
    @proxy.file(key, @mode, :persist => true) do |file|
      file.write "write me"
    end
    proxy_path.read.should =~ /write me$/
  end
end

shared_examples "append" do
  it "should correctly append" do
    create_remote("hello")
    @proxy.file(key, @mode, :persist => true) do |file|
      file.write "goodbye"
      should_log /upload/
    end
    proxy_path.read.should == "hellogoodbye"
  end
end

shared_examples "create" do

  it "should create remote" do
    should_log /upload/
    file = @proxy.file(key, @mode)
    create_proxy("upload me")
    file.close
    remote_body.should == "upload me"
  end

  it "should not create remote if proxy is deleted" do
    should_not_log /upload/
    @proxy.file(key, @mode) do |file|
      file.write("ignore me")
      proxy_path.unlink
    end
    expect {remote_body}.should raise_error
  end

  it "should not create remote if :synchronize => false" do
    should_not_log /upload/
    file = @proxy.file(key, @mode)
    create_proxy("ignore me")
    file.close(:synchronize => false)
    expect {remote_body}.should raise_error
  end

  it "should create remote asynchronously if :synchronize => async" do
    should_log /upload/
    file = @proxy.file(key, @mode)
    create_proxy("upload me in thread")
    Thread.should_receive(:new) { |&block|
      expect {remote_body}.should raise_error
      block.call
    }
    file.close(:synchronize => :async)
    remote_body.should == "upload me in thread"
  end

end

shared_examples "update" do

  it "should overwrite remote" do
    create_remote("overwrite me")
    remote_body.should == "overwrite me"
    file = @proxy.file(key, @mode)
    create_proxy("upload me")
    should_log /upload/
    file.close
    remote_body.should == "upload me"
  end

  it "should overwrite remote asynchronously if :synchronize => :async" do
    create_remote("overwrite me")
    file = @proxy.file(key, @mode)
    create_proxy("upload me")
    Thread.should_receive(:new) { |&block|
      remote_body.should == "overwrite me"
      block.call
    }
    should_log /upload/
    file.close(:synchronize => :async)
    remote_body.should == "upload me"
  end

  it "should not overwrite remote if proxy is deleted" do
    should_not_log /upload/
    create_remote("keep me")
    @proxy.file(key, @mode) do |file|
      file.write("ignore me")
      proxy_path.unlink
    end
    remote_body.should == "keep me"
  end

  it "should not overwrite remote if :synchronize => false" do
    should_not_log /upload/
    create_remote("keep me")
    file = @proxy.file(key, @mode)
    create_proxy("ignore me")
    file.close(:synchronize => false)
    remote_body.should == "keep me"
  end

end

shared_examples "persistence" do
  it "should delete proxy on close" do
    create_remote("whatever")
    file = @proxy.file(key, @mode)
    proxy_path.should be_exist
    file.close
    proxy_path.should_not be_exist
  end

  it "should delete proxy on close (block form)" do
    create_remote("whatever")
    @proxy.file(key, @mode) do |file|
      proxy_path.should be_exist
    end
    proxy_path.should_not be_exist
  end

  it "should not delete proxy if persisting" do
    create_remote("whatever")
    @proxy.file(key, @mode, :persist => true) do |file|
      proxy_path.should be_exist
    end
    proxy_path.should be_exist
  end

  it "close should override persist true" do
    create_remote("whatever")
    file = @proxy.file(key, @mode)
    proxy_path.should be_exist
    file.close(:persist => true)
    proxy_path.should be_exist
  end

  it "close should override persist false" do
    create_remote("whatever")
    file = @proxy.file(key, @mode, :persist => true)
    proxy_path.should be_exist
    file.close(:persist => false)
    proxy_path.should_not be_exist
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
    expect { @proxy.file(key, "xyz") }.should raise_error(ArgumentError)
  end

  it "should have a nice to_s" do
    @proxy.file(key, "w") {|f|
      f.to_s.should include f.path
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
