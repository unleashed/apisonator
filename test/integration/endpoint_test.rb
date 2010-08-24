require File.dirname(__FILE__) + '/../test_helper'

class WebApplicationTest < Test::Unit::TestCase
  include TestHelpers::Integration

  def test_on_invalid_path_responds_with_404
    post '/foo.html'
    assert_equal 404, last_response.status
  end

  def test_on_invalid_http_method_responds_with_404
    get '/transactions.xml'
    assert_equal 404, last_response.status
    
    post '/transaction/authorize.xml'
    assert_equal 404, last_response.status
  end

  # TODO: test unexpected error response
end