require 'contacts'

require 'rubygems'
require 'hpricot'
require 'md5'
require 'net/https'
require 'uri'
require 'yaml'
require 'json' unless defined? ActiveSupport::JSON

module Contacts
  # = How I can fetch Yahoo Contacts?
  # To gain access to a Yahoo user's data in the Yahoo Address Book Service, 
  # a third-party developer first must ask the owner for permission. You must
  # do that through Yahoo Browser Based Authentication (BBAuth).
  # 
  # This library give you access to Yahoo BBAuth and Yahoo Address Book API. 
  # Just follow the steps below and be happy!
  # 
  # === Registering your app
  # First of all, follow the steps in this 
  # page[http://developer.yahoo.com/wsregapp/] to register your app. If you need
  # some help with that form, you can get it
  # here[http://developer.yahoo.com/auth/appreg.html]. Just two tips: inside
  # <b>Required access scopes</b> in that registration form, choose
  # <b>Yahoo! Address Book with Read Only access</b>. Inside 
  # <b>Authentication method</b> choose <b>Browser Based Authentication</b>.
  #
  # === Configuring your Yahoo YAML
  # After registering your app, you will have an <b>application id</b> and a
  # <b>shared secret</b>. Use their values to fill in the config/contacts.yml 
  # file.
  #
  # === Authenticating your user and fetching his contacts
  # 
  #   yahoo = Contacts::Yahoo.new
  #   auth_url = yahoo.get_authentication_url
  # 
  # Use that *auth_url* to redirect your user to Yahoo BBAuth. He will authenticate
  # there and Yahoo will redirect to your application entrypoint URL (that you provided
  # while registering your app with Yahoo). You have to get the path of that 
  # redirect, let's call it path (if you're using Rails, you can get it through
  # request.request_uri, in the context of an action inside ActionController)
  #
  # Now, to fetch his contacts, just do this:
  #
  #   contacts = wl.contacts(path)
  #   #-> [ ['Fitzgerald', 'fubar@gmail.com', 'fubar@example.com'],
  #         ['William Paginate', 'will.paginate@gmail.com'], ...
  #       ]
  #--
  # This class has two responsibilities:
  # 1. Access the Yahoo Address Book API through Delegated Authentication
  # 2. Import contacts from Yahoo Mail and deliver it inside an Array
  #
  class Yahoo
    AUTH_DOMAIN = "https://api.login.yahoo.com"
    AUTH_PATH = "/WSLogin/V1/wslogin?appid=#appid&ts=#ts"
    CREDENTIAL_PATH = "/WSLogin/V1/wspwtoken_login?appid=#appid&ts=#ts&token=#token"
    ADDRESS_BOOK_DOMAIN = "address.yahooapis.com"
    ADDRESS_BOOK_PATH = "/v1/searchContacts?format=json&fields=name,email&appid=#appid&WSSID=#wssid"
    CONFIG_FILE = File.dirname(__FILE__) + '/../config/contacts.yml'

    attr_reader :appid, :secret, :token, :wssid, :cookie
    
    # Initialize a new Yahoo object.
    #    
    # ==== Paramaters
    # * config_file <String>:: The contacts YAML config file name
    #--
    # You can check an example of a config file inside config/ directory
    #
    def initialize(config_file=CONFIG_FILE)
      confs = YAML.load_file(config_file)['yahoo']
      @appid = confs['appid']
      @secret = confs['secret']
    end

    # Yahoo Address Book API need to authenticate the user that is giving you
    # access to his contacts. To do that, you must give him a URL. This method
    # generates that URL. The user must access that URL, and after he has done
    # authentication, hi will be redirected to your application.
    #
    def get_authentication_url
      path = AUTH_PATH.clone
      path.sub!(/#appid/, @appid)

      timestamp = Time.now.utc.to_i
      path.sub!(/#ts/, timestamp.to_s)
      
      signature = MD5.hexdigest(path + @secret)
      return AUTH_DOMAIN + "#{path}&sig=#{signature}"
    end

    # This method return the user's contacts inside an Array in the following
    # format:
    #
    #   [ 
    #     ['Brad Fitzgerald', 'fubar@gmail.com'],
    #     [nil, 'nagios@hotmail.com'],
    #     ['William Paginate', 'will.paginate@yahoo.com']  ...
    #   ]
    #
    # ==== Paramaters
    # * path <String>:: The path of the redirect request that Yahoo sent to you
    # after authenticating the user
    #
    def contacts(path)
      begin
        validate_signature(path)
        credentials = access_user_credentials()
        parse_credentials(credentials)
        contacts_json = access_address_book_api()
        Yahoo.parse_contacts(contacts_json)
      rescue Exception => e
        "Error #{e.class}: #{e.message}."
      end
    end

    # This method processes and validates the redirect request that Yahoo send to
    # you. Validation is done to verify that the request was really made by
    # Yahoo. Processing is done to get the token.
    #
    # ==== Paramaters
    # * path <String>:: The path of the redirect request that Yahoo sent to you
    # after authenticating the user
    #
    def validate_signature(path)
      path.match(/^(.+)&sig=(\w{32})$/)
      path_without_sig = $1
      sig = $2

      if sig == MD5.hexdigest(path_without_sig + @secret)
        path.match(/token=(.+?)&/)
        @token = $1
        return true
      else
        raise 'Signature not valid. This request may not have been sent from Yahoo.'
      end
    end

    # This method accesses Yahoo to retrieve the user's credentials.
    #
    def access_user_credentials
      url = get_credential_url()
      uri = URI.parse(url)

      http = http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      response = nil
      http.start do |http|
         request = Net::HTTP::Get.new("#{uri.path}?#{uri.query}")
         response = http.request(request)
      end

      return response.body
    end

    # This method generates the URL that you must access to get user's
    # credentials.
    #
    def get_credential_url
      path = CREDENTIAL_PATH.clone
      path.sub!(/#appid/, @appid)

      path.sub!(/#token/, @token)

      timestamp = Time.now.utc.to_i
      path.sub!(/#ts/, timestamp.to_s)

      signature = MD5.hexdigest(path + @secret)
      return AUTH_DOMAIN + "#{path}&sig=#{signature}"
    end

    # This method parses the user's credentials to generate the WSSID and 
    # Coookie that are needed to give you access to user's address book.
    #
    # ==== Paramaters
    # * xml <String>:: A String containing the user's credentials
    #
    def parse_credentials(xml)
      doc = Hpricot::XML(xml)
      @wssid = doc.at('/BBAuthTokenLoginResponse/Success/WSSID').inner_text.strip
      @cookie = doc.at('/BBAuthTokenLoginResponse/Success/Cookie').inner_text.strip
    end

    # This method accesses the Yahoo Address Book API and retrieves the user's
    # contacts in JSON.
    #
    def access_address_book_api
      http = http = Net::HTTP.new(ADDRESS_BOOK_DOMAIN, 80)

      response = nil
      http.start do |http|
         path = ADDRESS_BOOK_PATH.clone
         path.sub!(/#appid/, @appid)
         path.sub!(/#wssid/, @wssid)

         request = Net::HTTP::Get.new(path, {'Cookie' => @cookie})
         response = http.request(request)
      end

      return response.body
    end
    
    # This method parses the JSON contacts document and returns an array
    # contaning all the user's contacts.
    #
    # ==== Parameters
    # * json <String>:: A String of user's contacts in JSON format
    #
    def self.parse_contacts(json)
      contacts = []
      people = if defined? ActiveSupport::JSON
        ActiveSupport::JSON.decode(json)
      else
        JSON.parse(json)
      end

      people['contacts'].each do |contact|
        name = nil
        email = nil
        contact['fields'].each do |field|
          case field['type']
          when 'email'
            email = field['data']
            email.strip!
          when 'name'
            name = "#{field['first']} #{field['last']}"
            name.strip!
          end
        end
        contacts.push Contact.new(email, name)
      end
      return contacts
    end

  end
end
