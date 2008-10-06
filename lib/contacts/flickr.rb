require 'contacts'

require 'rubygems'
require 'hpricot'
require 'md5'
require 'cgi'
require 'time'
require 'zlib'
require 'stringio'
require 'net/http'

module Contacts
  
  class Flickr
    DOMAIN = 'api.flickr.com'
    ServicesPath = '/services/rest/'

    def self.frob_url(key, secret)
      url_for(:api_key => key, :secret => secret, :method => 'flickr.auth.getFrob')
    end
    
    def self.frob_from_response(response)
      doc = Hpricot::XML response.body
      doc.at('frob').inner_text
    end
    
    def self.authentication_url_for_frob(frob, key, secret)
      params = { :api_key => key, :secret => secret, :perms => 'read', :frob => frob }
      'http://www.flickr.com/services/auth/?' + query_string(params)
    end

    def self.authentication_url(key, secret)
      response = http_start do |flickr|
        flickr.get(frob_url(key, secret))
      end
      authentication_url_for_frob(frob_from_response(response), key, secret)
    end
    
    def self.token_url(key, secret, frob)
      params = { :api_key => key, :secret => secret, :frob => frob, :method => 'flickr.auth.getToken' }
      url_for(params)
    end
    
    def self.get_token_from_frob(key, secret, frob)
      response = http_start do |flickr|
        flickr.get(token_url(key, secret, frob))
      end
      doc = Hpricot::XML response.body
      doc.at('token').inner_text
    end
    
    private
      # Use the key-sorted version of the parameters to construct
      # a string, to which the secret is prepended.
      
      def self.sort_params(params)
        params.sort do |a,b|
          a.to_s <=> b.to_s
        end
      end
      
      def self.string_to_sign(params, secret)
        string_to_sign = secret + sort_params(params).inject('') do |str, pair|
          key, value = pair
          str + key.to_s + value.to_s
        end
      end

      # Get the MD5 digest of the string to sign
      def self.get_signature(params, secret)
        ::Digest::MD5.hexdigest(string_to_sign(params, secret))
      end
      
      def self.query_string(params)
        secret = params.delete(:secret)
        params[:api_sig] = get_signature(params, secret)
        
        params.inject([]) do |arr, pair|
          key, value = pair
          arr << "#{key}=#{value}"
        end.join('&')
      end
      
      def self.url_for(params)
        ServicesPath + '?' + query_string(params)
      end
      
      def self.http_start(ssl = false)
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
        out.puts "----\n#{response.body}\n----" unless response.body.empty?
      end
  end
  
end