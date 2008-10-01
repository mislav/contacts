require File.dirname(__FILE__) + '/../spec_helper'
require 'contacts/windows_live'

describe Contacts::WindowsLive do

  before(:each) do
    @path = Dir.getwd + '/spec/feeds/'
    @wl = Contacts::WindowsLive.new(@path + 'contacts.yml')
  end
  
  it 'parse the XML contacts document' do
    contacts = Contacts::WindowsLive.parse_xml(contacts_xml)
    contacts.should == [  [nil, 'froz@gmail.com'], 
                          ['Rafael Timbo', 'timbo@hotmail.com'], 
                          [nil, 'betinho@hotmail.com']
                       ]
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
