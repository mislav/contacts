require 'cgi'

module Contacts
  # AuthSub proxy authentication is used by web applications that need to
  # authenticate their users to Google Accounts.
  # 
  # http://code.google.com/apis/contacts/developers_guide_protocol.html#auth_sub
  module Gmail
    AuthSubURL = 'https://www.google.com/accounts/AuthSubRequest'
    # next / scope / secure / session
    AuthScope = 'http://www.google.com/m8/feeds/'
    FetchURL = 'http://www.google.com/m8/feeds/contacts/%s/base'
    # max-results / start-index / updated-min / orderby lastmodified / sortorder

    def self.authentication_url(target, options = {})
      params = { :next => target,
                 :scope => AuthScope,
                 :secure => false,
                 :session => false
               }.merge(options)
               
      query = params.inject [] do |url, pair|
        value = case pair.last
          when TrueClass; 1
          when FalseClass; 0
          else pair.last
          end
        
        url << "#{pair.first}=#{CGI::escape(value.to_s)}"
      end.join('&')

      AuthSubURL + '?' + query
    end
  end
end
