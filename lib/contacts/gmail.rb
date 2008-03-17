require 'contacts'
require 'cgi'
require 'net/http'
require 'net/https'
require 'rubygems'
require 'hpricot'
require 'date'
require 'zlib'
require 'stringio'

module Contacts
  # Web applications should use
  # AuthSub[http://code.google.com/apis/contacts/developers_guide_protocol.html#auth_sub]
  # proxy authentication to get an authentication token for a Google account.
  # 
  # First, get the user to follow the following URL:
  # 
  #   Contacts::Gmail.authentication_url('http://mysite.com/invite')
  #
  # After he authenticates successfully, Google will redirect him back to the target URL
  # (specified as argument above) and provide the token GET parameter. Use it to create a
  # new instance of this class and request the contact list:
  #
  #   gmail = Contacts::Gmail.new('example@gmail.com', params[:token])
  #   contacts = gmail.contacts
  #   #-> [ ['Fitzgerald', 'fubar@gmail.com', 'fubar@example.com'],
  #         ['William Paginate', 'will.paginate@gmail.com'], ...
  #         ]
  class Gmail
    DOMAIN      = 'www.google.com'
    AuthSubPath = '/accounts/AuthSub' # all variants go over HTTPS
    AuthScope   = "http://#{DOMAIN}/m8/feeds/"

    # URL to Google site where user authenticates. Afterwards, Google redirects to your
    # site with the URL specified as +target+.
    #
    # Options are:
    # * <tt>:scope</tt> -- the AuthSub scope in which the resulting token is valid
    #   (default: "http://www.google.com/m8/feeds/")
    # * <tt>:secure</tt> -- boolean indicating whether the token will be secure
    #   (default: false)
    # * <tt>:session</tt> -- boolean indicating if the token can be exchanged for a session token
    #   (default: false)
    def self.authentication_url(target, options = {})
      params = { :next => target,
                 :scope => AuthScope,
                 :secure => false,
                 :session => false
               }.merge(options)
               
      query = params.inject [] do |url, pair|
        unless pair.last.nil?
          value = case pair.last
            when TrueClass; 1
            when FalseClass; 0
            else pair.last
            end
          
          url << "#{pair.first}=#{CGI.escape(value.to_s)}"
        end
        url
      end.join('&')

      "https://#{DOMAIN}#{AuthSubPath}Request?#{query}"
    end

    def self.session_token(token)
      response = Net::HTTP.start(DOMAIN) do |google|
        google.use_ssl
        google.verify_mode = OpenSSL::SSL::VERIFY_NONE
        google.get(AuthSubPath + 'SessionToken', auth_headers(token))
      end

      pair = response.body.split(/\s+/).detect {|p| p.index('Token') == 0 }
      pair.split('=').last if pair
    end

    def self.auth_headers(token)
      { 'Authorization' => %(AuthSub token=#{token.to_s.inspect}) }
    end

    # User ID (email) and token are required here. By default, an AuthSub token from
    # Google is one-time only, which means you can only make a single request with it.
    def initialize(user_id, token)
      @user = user_id.to_s
      @headers = { 'Accept-Encoding' => 'gzip' }.update(self.class.auth_headers(token))
      @base_path = "/m8/feeds/contacts/#{CGI.escape(@user)}/base"
    end

    def get(params)
      response = Net::HTTP.start(DOMAIN) do |google|
        google.get(@base_path + '?' + query_string(params), @headers)
      end

      raise FetchingError.new(response) unless response.is_a? Net::HTTPSuccess

      response
    end

    # Timestamp of last update (DateTime). This value is available only after the XML
    # document has been parsed; for instance after fetching the contact list.
    def updated_at
      @updated_at ||= DateTime.parse @updated_string if @updated_string
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

    protected
      
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
        entries = []
        
        if updated_node = doc.at('/feed/updated')
          @updated_string = updated_node.inner_text
        end
        
        (doc / '/feed/entry').each do |entry|
          email_nodes = entry / 'gd:email[@address]'
          
          unless email_nodes.empty?
            title_node = entry.at('/title')
            name = title_node ? title_node.inner_text : nil
            
            person = email_nodes.inject [name] do |p, e|
              p << e['address'].to_s
            end
            entries << person
          end
        end

        entries
      end

      def query_string(params)
        params.inject [] do |url, pair|
          value = pair.last
          unless value.nil?
            key = case pair.first
              when :limit
                'max-results'
              when :offset
                value = value.to_i + 1
                'start-index'
              when :order
                url << 'sortorder=descending' if params[:descending].nil?
                'orderby'
              when :descending
                value = value ? 'descending' : 'ascending'
                'sortorder'
              when :updated_after
                value = value.strftime("%Y-%m-%dT%H:%M:%S%Z") if value.respond_to? :strftime
                'updated-min'
              else pair.first
              end
            
            url << "#{key}=#{CGI.escape(value.to_s)}"
          end
          url
        end.join('&')
      end
  end
end
