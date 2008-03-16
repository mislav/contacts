require 'contacts'
require 'cgi'
require 'net/http'
require 'rubygems'
require 'hpricot'
require 'date'

module Contacts
  # AuthSub proxy authentication is used by web applications that need to
  # authenticate their users to Google Accounts.
  # 
  # http://code.google.com/apis/contacts/developers_guide_protocol.html#auth_sub
  class Gmail
    DOMAIN     = 'www.google.com'
    AuthSubURL = "https://#{DOMAIN}/accounts/AuthSubRequest"
    AuthScope  = "http://#{DOMAIN}/m8/feeds/"

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

      AuthSubURL + '?' + query
    end

    attr_reader :uri
    
    def initialize(email, token, options = {})
      @token = token.to_s
      @email = email.to_s
      @headers = {
        'Authorization' => %(AuthSub token="#{@token}"),
        'Accept-Encoding' => 'gzip'
      }
      @uri = URI.parse AuthScope + "contacts/#{CGI.escape(@email)}/base"
      
      @params = { :limit => 200 }.merge(options)
    end

    def query_string
      @params.inject [] do |url, pair|
        value = pair.last
        unless value.nil?
          # max-results / start-index / updated-min / orderby lastmodified / sortorder
          key = case pair.first
            when :limit
              'max-results'
            when :offset
              value = value.to_i + 1
              'start-index'
            when :order
              url << 'sortorder=descending' if @params[:descending].nil?
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

    def get
      response = Net::HTTP.start(uri.host) do |google|
        google.get(uri.path + '?' + query_string, @headers)
      end

      unless response.is_a? Net::HTTPSuccess
        raise FetchingError.new(response)
      end

      response
    end

    def response_body
      @response = get unless @response
      
      unless @response['Content-Encoding'] == 'gzip'
        @response.body
      else
        require 'zlib'
        require 'stringio'

        gzipped = StringIO.new(@response.body)
        Zlib::GzipReader.new(gzipped).read
      end
    end

    def parse
      @doc = Hpricot::XML response_body
      @updated_string = @doc.at('/feed/updated').inner_text
    end

    def updated_at
      @updated_at ||= DateTime.parse @updated_string if @updated_string
    end

    def updated_at_string
      @updated_string
    end

    def contacts
      parse
      all = []
      (@doc / '/feed/entry').each do |entry|
        title_node = entry.at('/title')
        email_nodes = entry / 'gd:email[@address]'
        if title_node or !email_nodes.zero?
          person = [title_node ? title_node.inner_text : nil]
          person.concat email_nodes.map {|e| e['address'].to_s }
          all << person
        end
      end
      all
    end
  end
end
