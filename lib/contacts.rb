require 'contacts/version'

module Contacts
  
  Identifier = 'Ruby Contacts v' + VERSION::STRING
  
  # An object that represents a single contact
  class Contact
    attr_reader :name, :username, :emails
    
    def initialize(email, name = nil, username = nil)
      @emails = []
      @emails << email if email
      @name = name
      @username = username
    end
    
    def email
      @emails.first
    end
    
    def inspect
      %!#<Contacts::Contact "#{name}"#{email ? " (#{email})" : ''}>!
    end
  end
  
  def self.verbose?
    'irb' == $0
  end
  
  class Error < StandardError
  end
  
  class TooManyRedirects < Error
    attr_reader :response, :location
    
    MAX_REDIRECTS = 2
    
    def initialize(response)
      @response = response
      @location = @response['Location']
      super "exceeded maximum of #{MAX_REDIRECTS} redirects (Location: #{location})"
    end
  end
  
end
