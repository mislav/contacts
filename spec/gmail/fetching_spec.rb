require 'spec_helper'
require 'contacts/google'

describe Contacts::Google do

  before :each do
    @gmail = create
  end
  
  def create
    Contacts::Google.new('dummytoken')
  end
  
  after :each do
    FakeWeb.clean_registry
  end

  describe 'fetches contacts feed via HTTP GET' do
    it 'with defaults' do
      FakeWeb::register_uri(:get, 'www.google.com/m8/feeds/contacts/default/thin',
        :string => 'thin results',
        :verify => lambda { |req|
          req['Authorization'].should == %(AuthSub token="dummytoken")
          req['Accept-Encoding'].should == 'gzip'
          req['User-Agent'].should == "Ruby Contacts v#{Contacts::VERSION::STRING} (gzip)"
        }
      )
        
      response = @gmail.get({})
      response.body.should == 'thin results'
    end
    
    it 'with explicit user ID and full projection' do
      @gmail = Contacts::Google.new('dummytoken', 'person@example.com')
      @gmail.projection = 'full'
      
      FakeWeb::register_uri(:get, 'www.google.com/m8/feeds/contacts/person%40example.com/full',
        :string => 'full results'
      )

      response = @gmail.get({})
      response.body.should == 'full results'
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

  it 'raises a fetching error when something goes awry' do
    FakeWeb::register_uri(:get, 'www.google.com/m8/feeds/contacts/default/thin',
      :status => [404, 'YOU FAIL']
    )
      
    lambda {
      @gmail.get({})
    }.should raise_error(Net::HTTPServerException)
  end

  it 'parses the resulting feed into name/email pairs' do
    @gmail.stubs(:get)
    @gmail.expects(:response_body).returns(sample_xml('google-single'))

    found = @gmail.contacts
    found.size.should == 1
    contact = found.first
    contact.name.should == 'Fitzgerald'
    contact.emails.should == ['fubar@gmail.com']
  end

  it 'parses a complex feed into name/email pairs' do
    @gmail.stubs(:get)
    @gmail.expects(:response_body).returns(sample_xml('google-many'))

    found = @gmail.contacts
    found.size.should == 3
    found[0].name.should == 'Elizabeth Bennet'
    found[0].emails.should == ['liz@gmail.com', 'liz@example.org']
    found[1].name.should == 'William Paginate'
    found[1].emails.should == ['will_paginate@googlegroups.com']
    found[2].name.should be_nil
    found[2].emails.should == ['anonymous@example.com']
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
    end
    
    it 'abstracts ugly parameters behind nicer ones' do
      expect_params 'max-results' => '25',
                    'orderby' => 'lastmodified',
                    'sortorder' => 'ascending',
                    'start-index' => '11',
                    'updated-min' => 'datetime'

      @gmail.contacts :limit => 25,
        :offset => 10,
        :order => 'lastmodified',
        :descending => false,
        :updated_after => 'datetime'
    end

    it 'should have implicit :descending with :order' do
      expect_params 'orderby' => 'lastmodified', 
                    'sortorder' => 'descending',
                    'max-results' => '200'
                    
      @gmail.contacts :order => 'lastmodified'
    end

    it 'should have default :limit of 200' do
      expect_params 'max-results' => '200'
      @gmail.contacts
    end

    it 'should skip nil values in parameters' do
      expect_params 'start-index' => '1'
      @gmail.contacts :limit => nil, :offset => 0
    end

    def expect_params(params)
      query_string = Contacts::Google.query_string(params)
      FakeWeb::register_uri(:get, "www.google.com/m8/feeds/contacts/default/thin?#{query_string}")
    end
    
  end
  
  describe 'Retrieving all contacts (in chunks)' do
    
    before :each do
      @gmail = create
    end
    
    it 'should make only one API call when no more is needed' do
      @gmail.expects(:contacts).with(instance_of(Hash)).once.returns((0..8).to_a)

      @gmail.all_contacts({}, 10).should == (0..8).to_a
    end
    
    it 'should make multiple calls to :contacts when needed' do
      @gmail.expects(:contacts).with(has_entries(:offset => 0 , :limit => 10)).returns(( 0..9 ).to_a)
      @gmail.expects(:contacts).with(has_entries(:offset => 10, :limit => 10)).returns((10..19).to_a)
      @gmail.expects(:contacts).with(has_entries(:offset => 20, :limit => 10)).returns((20..24).to_a)
      
      @gmail.all_contacts({}, 10).should == (0..24).to_a
    end
    
    it 'should make one extra API call when not sure whether there are more contacts' do
      @gmail.expects(:contacts).with(has_entries(:offset => 0 , :limit => 10)).returns((0..9).to_a)
      @gmail.expects(:contacts).with(has_entries(:offset => 10, :limit => 10)).returns([])
      
      @gmail.all_contacts({}, 10).should == (0..9).to_a
    end
    
  end
  
end
