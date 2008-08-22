module Contacts
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
  
  class FetchingError < RuntimeError
    
  end
end
