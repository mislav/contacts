require 'contacts'

require 'rubygems'
require 'hpricot'
require 'cgi'
require 'time'
require 'zlib'
require 'stringio'
require 'net/http'
require 'net/https'

module Contacts
  # == Fetching Google Contacts
  # 
  # First, get the user to follow the following URL:
  # 
  #   Contacts::Google.authentication_url('http://mysite.com/invite')
  #
  # After he authenticates successfully to Google, it will redirect him back to the target URL
  # (specified as argument above) and provide the token GET parameter. Use it to create a
  # new instance of this class and request the contact list:
  #
  #   gmail = Contacts::Google.new(params[:token])
  #   contacts = gmail.contacts
  #   #-> [ ['Fitzgerald', 'fubar@gmail.com', 'fubar@example.com'],
  #         ['William Paginate', 'will.paginate@gmail.com'], ...
  #         ]
  #
  # == Storing a session token
  #
  # The basic token that you will get after the user has authenticated on Google is valid
  # for <b>only one request</b>. However, you can specify that you want a session token which
  # doesn't expire:
  # 
  #   Contacts::Google.authentication_url('http://mysite.com/invite', :session => true)
  #
  # When the user authenticates, he will be redirected back with a token that can be exchanged
  # for a session token with the following method:
  #
  #   token = Contacts::Google.sesion_token(params[:token])
  #
  # Now you have a permanent token. Store it with other user data so you can query the API
  # on his behalf without him having to authenticate on Google each time.
  class Google
    DOMAIN      = 'www.google.com'
    AuthSubPath = '/accounts/AuthSub' # all variants go over HTTPS
    ClientLogin = '/accounts/ClientLogin'
    FeedsPath   = '/m8/feeds/contacts/'
    
    # default options for #authentication_url
    def self.authentication_url_options
      @authentication_url_options ||= {
        :scope => "http://#{DOMAIN}#{FeedsPath}",
        :secure => false,
        :session => false
      }
    end
    
    # default options for #client_login
    def self.client_login_options
      @client_login_options ||= {
        :accountType => 'GOOGLE',
        :service => 'cp',
        :source => 'Contacts-Ruby'
      }
    end

    # URL to Google site where user authenticates. Afterwards, Google redirects to your
    # site with the URL specified as +target+.
    #
    # Options are:
    # * <tt>:scope</tt> -- the AuthSub scope in which the resulting token is valid
    #   (default: "http://www.google.com/m8/feeds/contacts/")
    # * <tt>:secure</tt> -- boolean indicating whether the token will be secure. Only available
    #   for registered domains.
    #   (default: false)
    # * <tt>:session</tt> -- boolean indicating if the token can be exchanged for a session token
    #   (default: false)
    def self.authentication_url(target, options = {})
      params = authentication_url_options.merge(options)
      params[:next] = target
      query = query_string(params)
      "https://#{DOMAIN}#{AuthSubPath}Request?#{query}"
    end

    # Makes an HTTPS request to exchange the given token with a session one. Session
    # tokens never expire, so you can store them in the database alongside user info.
    #
    # Returns the new token as string or nil if the parameter couldn't be found in response
    # body.
    def self.session_token(token)
      response = http_start do |google|
        google.get(AuthSubPath + 'SessionToken', authorization_header(token))
      end

      pair = response.body.split(/\n/).detect { |p| p.index('Token=') == 0 }
      pair.split('=').last if pair
    end
    
    # Alternative to AuthSub: using email and password.
    def self.client_login(email, password)
      response = http_start do |google|
        query = query_string(client_login_options.merge(:Email => email, :Passwd => password))
        puts "posting #{query} to #{ClientLogin}" if Contacts::verbose?
        google.post(ClientLogin, query)
      end

      pair = response.body.split(/\n/).detect { |p| p.index('Auth=') == 0 }
      pair.split('=').last if pair
    end
    
    attr_reader :user, :token, :headers
    attr_accessor :projection

    # A token is required here. By default, an AuthSub token from
    # Google is one-time only, which means you can only make a single request with it.
    def initialize(token, user_id = 'default', client = false)
      @user    = user_id.to_s
      @token   = token.to_s
      @headers = {
        'Accept-Encoding' => 'gzip',
        'User-Agent' => Identifier + ' (gzip)'
      }.update(self.class.authorization_header(@token, client))
      @projection = 'thin'
    end

    def get(params) # :nodoc:
      self.class.http_start(false) do |google|
        path = FeedsPath + CGI.escape(@user)
        google_params = translate_parameters(params)
        query = self.class.query_string(google_params)
        google.get("#{path}/#{@projection}?#{query}", @headers)
      end
    end

    # Timestamp of last update. This value is available only after the XML
    # document has been parsed; for instance after fetching the contact list.
    def updated_at
      @updated_at ||= Time.parse @updated_string if @updated_string
    end

    # Timestamp of last update as it appeared in the XML document
    def updated_at_string
      @updated_string
    end

    # Fetches, parses and returns the contact list.
    #
    # ==== Options
    # * <tt>:limit</tt> -- use a large number to fetch a bigger contact list (default: 200)
    # * <tt>:offset</tt> -- 0-based value, can be used for pagination
    # * <tt>:order</tt> -- currently the only value support by Google is "lastmodified"
    # * <tt>:descending</tt> -- boolean
    # * <tt>:updated_after</tt> -- string or time-like object, use to only fetch contacts
    #   that were updated after this date
    def contacts(options = {})
      params = { :limit => 200 }.update(options)
      response = get(params)
      parse_contacts response_body(response)
    end
    
    # Fetches contacts using multiple API calls when necessary
    def all_contacts(options = {}, chunk_size = 200)
      in_chunks(options, :contacts, chunk_size)
    end

    protected
    
      def in_chunks(options, what, chunk_size)
        returns = []
        offset = 0
        
        begin
          chunk = send(what, options.merge(:offset => offset, :limit => chunk_size))
          returns.push(*chunk)
          offset += chunk_size
        end while chunk.size == chunk_size 
        
        returns
      end
      
      def response_body(response)
        unless response['Content-Encoding'] == 'gzip'
          response.body
        else
          gzipped = StringIO.new(response.body)
          Zlib::GzipReader.new(gzipped).read
        end
      end
      
      def parse_contacts(body)
        doc = Hpricot::XML body
        contacts_found = []
        
        if updated_node = doc.at('/feed/updated')
          @updated_string = updated_node.inner_text
        end
        
        (doc / '/feed/entry').each do |entry|
          email_nodes = entry / 'gd:email[@address]'
          
          unless email_nodes.empty?
            title_node = entry.at('/title')
            name = title_node ? title_node.inner_text : nil
            contact = Contact.new(nil, name)
            contact.emails.concat email_nodes.map { |e| e['address'].to_s }
            contacts_found << contact
          end
        end

        contacts_found
      end
      
      # Constructs a query string from a Hash object
      def self.query_string(params)
        params.inject([]) do |all, pair|
          key, value = pair
          unless value.nil?
            value = case value
              when TrueClass;  '1'
              when FalseClass; '0'
              else value
              end

            all << "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
          end
          all
        end.join('&')
      end

      def translate_parameters(params)
        params.inject({}) do |all, pair|
          key, value = pair
          unless value.nil?
            key = case key
              when :limit
                'max-results'
              when :offset
                value = value.to_i + 1
                'start-index'
              when :order
                all['sortorder'] = 'descending' if params[:descending].nil?
                'orderby'
              when :descending
                value = value ? 'descending' : 'ascending'
                'sortorder'
              when :updated_after
                value = value.strftime("%Y-%m-%dT%H:%M:%S%Z") if value.respond_to? :strftime
                'updated-min'
              else key
              end
            
            all[key] = value
          end
          all
        end
      end
      
      def self.authorization_header(token, client = false)
        type = client ? 'GoogleLogin auth' : 'AuthSub token'
        { 'Authorization' => %(#{type}="#{token}") }
      end
      
      def self.http_start(ssl = true)
        port = ssl ? Net::HTTP::https_default_port : Net::HTTP::http_default_port
        http = Net::HTTP.new(DOMAIN, port)
        redirects = 0
        if ssl
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
        http.start

        begin
          response = yield(http)

          loop do
            inspect_response(response) if Contacts::verbose?

            case response
            when Net::HTTPSuccess
              break response
            when Net::HTTPRedirection
              if redirects == TooManyRedirects::MAX_REDIRECTS
                raise TooManyRedirects.new(response)
              end
              location = URI.parse response['Location']
              puts "Redirected to #{location}"
              response = http.get(location.path)
              redirects += 1
            else
              response.error!
            end
          end
        ensure
          http.finish
        end
      end

      def self.inspect_response(response, out = $stderr)
        out.puts response.inspect
        for name, value in response
          out.puts "#{name}: #{value}"
        end
        out.puts "----\n#{response_body response}\n----" unless response.body.empty?
      end
  end
end
