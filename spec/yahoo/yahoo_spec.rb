require 'spec_helper'
require 'contacts/yahoo'

describe Contacts::Yahoo do
  
  before(:each) do
    @path = Dir.getwd + '/spec/feeds/'
    @yahoo = Contacts::Yahoo.new(@path + 'contacts.yml')
  end

  it 'should generate an athentication URL' do
    auth_url = @yahoo.get_authentication_url()
    auth_url.should match(/https:\/\/api.login.yahoo.com\/WSLogin\/V1\/wslogin\?appid=i%3DB%26p%3DUw70JGIdHWVRbpqYItcMw--&ts=.*&sig=.*/)
  end

  it 'should have a simple interface to grab the contacts' do
    @yahoo.expects(:access_user_credentials).returns(read_file('yh_credential.xml'))
    @yahoo.expects(:access_address_book_api).returns(read_file('yh_contacts.txt'))

    redirect_path = '/?appid=i%3DB%26p%3DUw70JGIdHWVRbpqYItcMw--&token=AB.KoEg8vBwvJKFkwfcDTJEMKhGeAD6KhiDe0aZLCvoJzMeQG00-&appdata=&ts=1218501215&sig=d381fba89c7e9d3c14788720733c3fbf'
                            
    results = @yahoo.contacts(redirect_path)
    results.should have_contact('Hugo Barauna', 'hugo.barauna@gmail.com')
    results.should have_contact('Nina Benchimol', 'nina@hotmail.com')
    results.should have_contact('Andrea Dimitri', 'and@yahoo.com')
    results.should have_contact('Ricardo Fiorelli', 'ricardo@poli.usp.br')
    results.should have_contact('Priscila', 'pizinha@yahoo.com.br')
  end

  it 'should validate yahoo redirect signature' do
    redirect_path = '/?appid=i%3DB%26p%3DUw70JGIdHWVRbpqYItcMw--&token=AB.KoEg8vBwvJKFkwfcDTJEMKhGeAD6KhiDe0aZLCvoJzMeQG00-&appdata=&ts=1218501215&sig=d381fba89c7e9d3c14788720733c3fbf'

    @yahoo.validate_signature(redirect_path).should be_true
    @yahoo.token.should == 'AB.KoEg8vBwvJKFkwfcDTJEMKhGeAD6KhiDe0aZLCvoJzMeQG00-'
  end
  
  it 'should detect when the redirect is not valid' do
    redirect_path = '/?appid=i%3DB%26p%3DUw70JGIdHWVRbpqYItcMw--&token=AB.KoEg8vBwvJKFkwfcDTJEMKhGeAD6KhiDe0aZLCvoJzMeQG00-&appdata=&ts=1218501215&sig=de4fe4ebd50a8075f75dcc23f6aca04f'

    lambda{ @yahoo.validate_signature(redirect_path) }.should raise_error
  end
  
  it 'should generate the credential request URL' do
    redirect_path = '/?appid=i%3DB%26p%3DUw70JGIdHWVRbpqYItcMw--&token=AB.KoEg8vBwvJKFkwfcDTJEMKhGeAD6KhiDe0aZLCvoJzMeQG00-&appdata=&ts=1218501215&sig=d381fba89c7e9d3c14788720733c3fbf'
    @yahoo.validate_signature(redirect_path)

    @yahoo.get_credential_url.should match(/https:\/\/api.login.yahoo.com\/WSLogin\/V1\/wspwtoken_login\?appid=i%3DB%26p%3DUw70JGIdHWVRbpqYItcMw--&ts=.*&token=.*&sig=.*/)
  end
  
  it 'should parse the credential XML' do
    @yahoo.parse_credentials(read_file('yh_credential.xml'))

    @yahoo.wssid.should == 'tr.jZsW/ulc'
    @yahoo.cookie.should == 'Y=cdunlEx76ZEeIdWyeJNOegxfy.jkeoULJCnc7Q0Vr8D5P.u.EE2vCa7G2MwBoULuZhvDZuJNqhHwF3v5RJ4dnsWsEDGOjYV1k6snoln3RlQmx0Ggxs0zAYgbaA4BFQk5ieAkpipq19l6GoD_k8IqXRfJN0Q54BbekC_O6Tj3zl2wV3YQK6Mi2MWBQFSBsO26Tw_1yMAF8saflF9EX1fQl4N.1yBr8UXb6LLDiPQmlISq1_c6S6rFbaOhSZMgO78f2iqZmUAk9RmCHrqPJiHEo.mJlxxHaQsuqTMf7rwLEHqK__Gi_bLypGtaslqeWyS0h2J.B5xwRC8snfEs3ct_kLXT3ngP_pK3MeMf2pe1TiJ4JXVciY9br.KJFUgNd4J6rmQsSFj4wPLoMGCETfVc.M8KLiaFHasZqXDyCE7tvd1khAjQ_xLfQKlg1GlBOWmbimQ1FhdHnsVj3svXjEGquRh8JI2sHIQrzoiqAPBf9WFKQcH0t_1dxf4MOH.7gJaYDPEozCW5EcCsYjuHup9xJKxyTddh5pk8yUg5bURzA.TwPalExMKsbv.RWFBhzWKuTp5guNcqjmUHcCoT19_qFENHX41Xf3texAnsDDGj'
  end

  it 'should parse the contacts json response' do
    json = read_file('yh_contacts.txt')
    
    Contacts::Yahoo.parse_contacts(json).should have_contact('Hugo Barauna', 'hugo.barauna@gmail.com')
    Contacts::Yahoo.parse_contacts(json).should have_contact('Nina Benchimol', 'nina@hotmail.com')
    Contacts::Yahoo.parse_contacts(json).should have_contact('Andrea Dimitri', 'and@yahoo.com')
    Contacts::Yahoo.parse_contacts(json).should have_contact('Ricardo Fiorelli', 'ricardo@poli.usp.br')
    Contacts::Yahoo.parse_contacts(json).should have_contact('Priscila', 'pizinha@yahoo.com.br')
  end

  it 'should can be initialized by a YAML file' do
    @yahoo.appid.should == 'i%3DB%26p%3DUw70JGIdHWVRbpqYItcMw--'
    @yahoo.secret.should == 'a34f389cbd135de4618eed5e23409d34450'
  end

  def read_file(file)
    File.open(@path + file, 'r+').read
  end

  def have_contact(name, email)
    matcher_class = Class.new()
    matcher_class.instance_eval do 
      define_method(:matches?) {|some_contacts| some_contacts.any? {|a_contact| a_contact.name == name && a_contact.emails.include?(email)}}
    end
    matcher_class.new
  end
end
