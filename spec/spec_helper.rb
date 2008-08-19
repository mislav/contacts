require 'rubygems'
gem 'rspec', '~> 1.1.3'
require 'spec'

# add library's lib directory
$:.unshift File.dirname(__FILE__) + '/../lib'

module SampleFeeds
  FEED_DIR = File.dirname(__FILE__) + '/feeds/'
  
  def sample_xml(name)
    File.read "#{FEED_DIR}#{name}.xml"
  end
end

Spec::Runner.configure do |config|
  config.include SampleFeeds
  # config.predicate_matchers[:swim] = :can_swim?
  
  config.mock_with :mocha
end
