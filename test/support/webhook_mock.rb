require 'net/http'
require 'uri'
require 'json'

module RedmineWebhook
  class WebhookMock
    attr_reader :requests, :url
    
    def initialize(url = RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_URL)
      @url = url
      @requests = []
      @response_code = RedmineWebhook::HttpStatus::OK
      @response_body = RedmineWebhook::HttpResponseBody::OK
    end
    
    def stub_response(code: RedmineWebhook::HttpStatus::OK, body: RedmineWebhook::HttpResponseBody::OK)
      @response_code = code
      @response_body = body
    end
    
    def last_request
      @requests.last
    end
    
    def request_count
      @requests.size
    end
    
    def clear_requests
      @requests.clear
    end
    
    def capture_request(request)
      @requests << {
        method: request.method,
        uri: request.uri.to_s,
        headers: request.to_hash,
        body: request.body
      }
    end
    
    def verify_signature(request, secret)
      signature = request['X-Webhook-Signature']
      body = request.body || ''
      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
      ActiveSupport::SecurityUtils.secure_compare(signature, expected)
    end
    
    def parse_payload(request)
      JSON.parse(request.body) rescue {}
    end
    
    # Mock HTTP response for testing
    def self.mock_http_post(url, &block)
      uri = URI.parse(url)
      
      # Create a mock response
      response = Net::HTTPResponse.new('1.1', RedmineWebhook::HttpStatus::OK.to_s, RedmineWebhook::HttpResponseBody::OK)
      response.body = RedmineWebhook::HttpResponseBody::OK
      
      # If block given, yield the request details
      if block_given?
        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type'] = 'application/json'
        block.call(request, response)
      end
      
      response
    end
  end
end
