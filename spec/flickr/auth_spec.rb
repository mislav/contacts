require 'spec_helper'
require 'contacts/flickr'
require 'uri'

describe Contacts::Flickr, "authentication" do
  
  before(:each) do
    @f = Contacts::Flickr
  end
  
  describe "authentication for desktop apps" do
    # Key, secret and signature come from the Flickr API docs.
    # http://www.flickr.com/services/api/auth.howto.desktop.html
    it "should generate a correct url to retrieve a frob" do
      path, query = Contacts::Flickr.frob_url('9a0554259914a86fb9e7eb014e4e5d52', '000005fab4534d05').split('?')
      path.should == '/services/rest/'

      hsh = hash_from_query(query)
      hsh[:method].should == 'flickr.auth.getFrob'
      hsh[:api_key].should == '9a0554259914a86fb9e7eb014e4e5d52'
      hsh[:api_sig].should == '8ad70cd3888ce493c8dde4931f7d6bd0'
      hsh[:secret].should be_nil
    end

    it "should generate an authentication url from a response with a frob" do
      response = mock_response
      response.stubs(:body).returns sample_xml('flickr/auth.getFrob')
      Contacts::Flickr.frob_from_response(response).should == '934-746563215463214621'
    end

    # The :api_sig parameter is documented wronly in the Flickr API docs. It says the string
    # to sign ends in 'permswread', but this should be 'permsread' of course. Therefore
    # the :api_sig here does not correspond to the Flickr docs, but it makes the spec valid.
    it "should return an url to authenticate to containing a frob" do
      response = mock_response
      response.stubs(:body).returns sample_xml('flickr/auth.getFrob')
      @f.expects(:http_start).returns(response)
      uri = URI.parse @f.authentication_url('9a0554259914a86fb9e7eb014e4e5d52', '000005fab4534d05')
      
      uri.host.should == 'www.flickr.com'
      uri.scheme.should == 'http'
      uri.path.should == '/services/auth/'
      hsh = hash_from_query(uri.query)
      hsh[:api_key].should == '9a0554259914a86fb9e7eb014e4e5d52'
      hsh[:api_sig].should == '0d08a9522d152d2e43daaa2a932edf67'
      hsh[:frob].should == '934-746563215463214621'
      hsh[:perms].should == 'read'
      hsh[:secret].should be_nil
    end
    
    it "should get a token from a frob" do
      response = mock_response
      response.stubs(:body).returns sample_xml('flickr/auth.getToken')
      connection = mock('Connection')
      connection.expects(:get).with do |value|
        path, query = value.split('?')
        path.should == '/services/rest/'
        
        hsh = hash_from_query(query)
        hsh[:method].should == 'flickr.auth.getToken'
        hsh[:api_key].should == '9a0554259914a86fb9e7eb014e4e5d52'
        hsh[:api_sig].should == 'a5902059792a7976d03be67bdb1e98fd'
        hsh[:frob].should == '934-746563215463214621'
        hsh[:secret].should be_nil
        true
      end
      @f.expects(:http_start).returns(response).yields(connection)
      @f.get_token_from_frob('9a0554259914a86fb9e7eb014e4e5d52', '000005fab4534d05', '934-746563215463214621').should == '45-76598454353455'
    end
        
  end

  def hash_from_query(str)
    str.split('&').inject({}) do |hsh, pair|
      key, value = pair.split('=')
      hsh[key.to_sym] = value
      hsh
    end
  end
end
