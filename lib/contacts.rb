module Contacts
  class FetchingError < RuntimeError
    attr_reader :response
    
    def initialize(response)
      @response = response
      super "expected HTTPSuccess, got #{response.class} (#{response.code} #{response.message})"
    end
  end
end
