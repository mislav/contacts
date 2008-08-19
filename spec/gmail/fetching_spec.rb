require File.dirname(__FILE__) + '/../spec_helper'
require 'contacts/google'

describe Contacts::Google do

  before :each do
    @gmail = create
  end

  describe 'fetches contacts feed via HTTP GET' do
    it 'with defaults' do
      @gmail.expects(:query_string).returns('a=b')
      connection = mock('HTTP connection')
      response = mock_response
      Net::HTTP.expects(:start).with('www.google.com').yields(connection).returns(response)
      connection.expects(:get).with('/m8/feeds/contacts/default/thin?a=b', {
          'Authorization' => %(AuthSub token="dummytoken"),
          'Accept-Encoding' => 'gzip'
        })

      @gmail.get({})
    end
    
    it 'with explicit user ID and full projection' do
      @gmail = Contacts::Google.new('dummytoken', 'person@example.com')
      @gmail.projection = 'full'
      @gmail.expects(:query_string).returns('')
      connection = mock('HTTP connection')
      response = mock_response
      Net::HTTP.expects(:start).yields(connection).returns(response)
      connection.expects(:get).with('/m8/feeds/contacts/person%40example.com/full?', anything)

      @gmail.get({})
    end
    
    def mock_response(success = true)
      response = mock('HTTP response')
      response.stubs(:is_a?).with(Net::HTTPSuccess).returns(success)
      response
    end
  end

  it 'handles a normal response body' do
    response = mock('HTTP response')
    @gmail.expects(:get).returns(response)

    response.expects(:'[]').with('Content-Encoding').returns(nil)
    response.expects(:body).returns('<feed/>')

    @gmail.expects(:parse_contacts).with('<feed/>')
    @gmail.contacts
  end

  it 'handles gzipped response' do
    response = mock('HTTP response')
    @gmail.expects(:get).returns(response)

    gzipped = StringIO.new
    gzwriter = Zlib::GzipWriter.new gzipped
    gzwriter.write(('a'..'z').to_a.join)
    gzwriter.close

    response.expects(:'[]').with('Content-Encoding').returns('gzip')
    response.expects(:body).returns gzipped.string

    @gmail.expects(:parse_contacts).with('abcdefghijklmnopqrstuvwxyz')
    @gmail.contacts
  end

  it 'raises a FetchingError when something goes awry' do
    response = mock('HTTP response', :code => 666, :class => Net::HTTPBadRequest, :message => 'oh my')
    Net::HTTP.expects(:start).returns(response)

    lambda {
      @gmail.get({})
    }.should raise_error(Contacts::FetchingError)
  end

  it 'parses the resulting feed into name/email pairs' do
    @gmail.stubs(:get)
    @gmail.expects(:response_body).returns(sample_xml('google-single'))

    @gmail.contacts.should == [['Fitzgerald', 'fubar@gmail.com']]
  end

  it 'parses a complex feed into name/email pairs' do
    @gmail.stubs(:get)
    @gmail.expects(:response_body).returns(sample_xml('google-many'))

    @gmail.contacts.should == [
      ['Elizabeth Bennet', 'liz@gmail.com', 'liz@example.org'],
      ['William Paginate', 'will_paginate@googlegroups.com'],
      [nil, 'anonymous@example.com']
    ]
  end

  it 'makes modification time available after parsing' do
    @gmail.updated_at.should be_nil
    @gmail.stubs(:get)
    @gmail.expects(:response_body).returns(sample_xml('google-single'))

    @gmail.contacts
    u = @gmail.updated_at
    u.year.should == 2008
    u.day.should == 5
    @gmail.updated_at_string.should == '2008-03-05T12:36:38.836Z'
  end

  describe 'GET query parameter handling' do
    
    before :each do
      @gmail = create
      @gmail.stubs(:response_body)
      @gmail.stubs(:parse_contacts)
      
      @connection = mock('HTTP connection')
      response = mock('HTTP response')
      response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
      Net::HTTP.stubs(:start).yields(@connection).returns(response)
    end
    
    it 'abstracts ugly parameters behind nicer ones' do
      expect_params %w( max-results=25
                        orderby=lastmodified
                        sortorder=ascending
                        start-index=11
                        updated-min=datetime )

      @gmail.contacts :limit => 25,
        :offset => 10,
        :order => 'lastmodified',
        :descending => false,
        :updated_after => 'datetime'
    end

    it 'should have implicit :descending with :order' do
      expect_params %w( orderby=lastmodified
                        sortorder=descending ), true
                        
      @gmail.contacts :order => 'lastmodified'
    end

    it 'should have default :limit of 200' do
      expect_params %w( max-results=200 )
      @gmail.contacts
    end

    it 'should skip nil values in parameters' do
      expect_params %w( start-index=1 )
      @gmail.contacts :limit => nil, :offset => 0
    end

    def expect_params(params, some = false)
      @connection.expects(:get).with() do |path, headers|
        pairs = path.split('?').last.split('&').sort
        unless some
          pairs.should == params
          pairs.size == params.size
        else
          params.each {|p| pairs.should include(p) }
          pairs.size >= params.size
        end
      end
    end
    
  end

  def create
    Contacts::Google.new('dummytoken')
  end

  def sample_xml(name)
    File.read File.dirname(__FILE__) + "/../feeds/#{name}.xml"
  end
end
