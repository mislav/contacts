require 'spec_helper'
require 'contacts/windows_live'

describe Contacts::WindowsLive do

  before(:each) do
    @path = Dir.getwd + '/spec/feeds/'
    @wl = Contacts::WindowsLive.new(@path + 'contacts.yml')
  end
  
  it 'parse the XML contacts document' do
    contacts = Contacts::WindowsLive.parse_xml(contacts_xml)
    
    contacts[0].name.should be_nil
    contacts[0].email.should == 'froz@gmail.com'
    contacts[1].name.should == 'Rafael Timbo'
    contacts[1].email.should == 'timbo@hotmail.com'
    contacts[2].name.should be_nil
    contacts[2].email.should == 'betinho@hotmail.com'

  end

  it 'should can be initialized by a YAML file' do
    wll = @wl.instance_variable_get('@wll')

    wll.appid.should == 'your_app_id'
    wll.securityalgorithm.should == 'wsignin1.0'
    wll.returnurl.should == 'http://yourserver.com/your_return_url'
  end

  def contacts_xml
    File.open(@path + 'wl_contacts.xml', 'r+').read
  end
end
