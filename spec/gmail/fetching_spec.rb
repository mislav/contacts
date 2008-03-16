require File.dirname(__FILE__) + '/../spec_helper'
require 'contacts/gmail'
require 'zlib'
require 'stringio'

describe Contacts::Gmail do
  it 'should be set to query contacts from a specific account' do
    create.uri.path.should include('/example%40gmail.com/')
  end

  it 'fetches contacts feed via HTTP GET' do
    gmail = create
    gmail.expects(:query_string).returns('a=b')
    connection = mock('HTTP connection')
    response = stub('HTTP response', :is_a? => true)
    Net::HTTP.expects(:start).with('www.google.com').yields(connection).returns(response)
    connection.expects(:get).with('/m8/feeds/contacts/example%40gmail.com/base?a=b', {
        'Authorization' => %(AuthSub token="dummytoken"),
        'Accept-Encoding' => 'gzip'
      })

    gmail.get
  end

  it 'handles gzipped response' do
    gmail = create
    response = mock('HTTP response')
    gmail.expects(:get).returns(response)

    gzipped = StringIO.new
    gzwriter = Zlib::GzipWriter.new gzipped
    gzwriter.write(('a'..'z').to_a.join)
    gzwriter.close

    response.expects(:'[]').with('Content-Encoding').returns('gzip')
    response.expects(:body).returns gzipped.string

    gmail.response_body.should == 'abcdefghijklmnopqrstuvwxyz'
  end

  it 'raises a FetchingError when something goes awry' do
    gmail = create
    response = mock('HTTP response', :code => 666, :class => Net::HTTPBadRequest, :message => 'oh my')
    Net::HTTP.expects(:start).returns(response)

    lambda {
      gmail.get
    }.should raise_error(Contacts::FetchingError)
  end

  it 'parses the resulting feed into name/email pairs' do
    gmail = create
    gmail.expects(:response_body).returns(sample_xml(:single))

    gmail.contacts.should == [['Fitzgerald', 'fubar@gmail.com']]
  end

  it 'makes modification time available after parsing' do
    gmail = create
    gmail.updated_at.should be_nil
    gmail.expects(:response_body).returns(sample_xml(:single))

    gmail.contacts
    u = gmail.updated_at
    u.year.should == 2008
    u.day.should == 5
    gmail.updated_at_string.should == '2008-03-05T12:36:38.836Z'
  end

  def create(options = {})
    Contacts::Gmail.new('example@gmail.com', 'dummytoken', options)
  end

  def sample_xml(name)
    File.read File.dirname(__FILE__) + "/../feeds/#{name}.xml"
  end
end
