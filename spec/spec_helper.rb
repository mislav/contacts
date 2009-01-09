require 'rubygems'
gem 'rspec', '~> 1.1.3'
require 'spec'
gem 'mocha', '~> 0.9.0'
require 'mocha'

require 'cgi'
require 'fake_web'
FakeWeb.allow_net_connect = false

module SampleFeeds
  FEED_DIR = File.dirname(__FILE__) + '/feeds/'
  
  def sample_xml(name)
    File.read "#{FEED_DIR}#{name}.xml"
  end
end

module HttpMocks
  def mock_response(type = :success)
    klass = case type
    when :success  then Net::HTTPSuccess
    when :redirect then Net::HTTPRedirection
    when :fail     then Net::HTTPClientError
    else type
    end
    
    klass.new(nil, nil, nil)
  end
  
  def mock_connection(ssl = true)
    connection = mock('HTTP connection')
    connection.stubs(:start)
    connection.stubs(:finish)
    if ssl
      connection.expects(:use_ssl=).with(true)
      connection.expects(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
    end
    connection
  end
end

Spec::Runner.configure do |config|
  config.include SampleFeeds, HttpMocks
  # config.predicate_matchers[:swim] = :can_swim?
  
  config.mock_with :mocha
end

module Mocha
  module ParameterMatchers
    def query_string(entries, partial = false)
      QueryStringMatcher.new(entries, partial)
    end
  end
end

class QueryStringMatcher < Mocha::ParameterMatchers::Base
  
  def initialize(entries, partial)
    @entries = entries
    @partial = partial
  end
  
  def matches?(available_parameters)
    string = available_parameters.shift.split('?').last
    broken = string.split('&').map { |pair| pair.split('=').map { |value| CGI.unescape(value) } }
    hash = Hash[*broken.flatten]
    
    if @partial
      has_entry_matchers = @entries.map do |key, value|
        Mocha::ParameterMatchers::HasEntry.new(key, value)
      end
      Mocha::ParameterMatchers::AllOf.new(*has_entry_matchers).matches?([hash])
    else
      @entries == hash
    end
  end
  
  def mocha_inspect
    "query_string(#{@entries.mocha_inspect})"
  end
  
end
