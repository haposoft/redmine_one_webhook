# Load the Redmine helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')
require 'securerandom'

# Load plugin files
require File.expand_path(File.dirname(__FILE__) + '/../lib/redmine_webhook')
require File.expand_path(File.dirname(__FILE__) + '/../lib/redmine_webhook/time_entry_patch')

# Apply TimeEntry patch
TimeEntry.include(RedmineWebhook::TimeEntryPatch) unless TimeEntry.included_modules.include?(RedmineWebhook::TimeEntryPatch)

# Load support files
Dir[File.expand_path(File.dirname(__FILE__) + '/support/**/*.rb')].each { |f| require f }

# HTTP Mocking using WebMock (if available) or manual stubbing
begin
  require 'webmock/minitest'
  WebMock.disable_net_connect!(allow_localhost: true)
rescue LoadError
  # WebMock not available, will use manual stubbing
  puts "WebMock not available, using manual HTTP stubbing"
end

module RedmineWebhook
  # HTTP Status Code Constants
  module HttpStatus
    # Success
    OK = 200
    CREATED = 201
    ACCEPTED = 202
    NO_CONTENT = 204
    
    # Client Error
    BAD_REQUEST = 400
    UNAUTHORIZED = 401
    FORBIDDEN = 403
    NOT_FOUND = 404
    UNPROCESSABLE_ENTITY = 422
    
    # Server Error
    INTERNAL_SERVER_ERROR = 500
    BAD_GATEWAY = 502
    SERVICE_UNAVAILABLE = 503
  end

  # HTTP Response Body Constants (corresponding to status codes)
  module HttpResponseBody
    # Success
    OK = 'OK'
    CREATED = 'Created'
    ACCEPTED = 'Accepted'
    NO_CONTENT = ''
    
    # Client Error
    BAD_REQUEST = 'Bad Request'
    UNAUTHORIZED = 'Unauthorized'
    FORBIDDEN = 'Forbidden'
    NOT_FOUND = 'Not Found'
    UNPROCESSABLE_ENTITY = 'Unprocessable Entity'
    
    # Server Error
    INTERNAL_SERVER_ERROR = 'Internal Server Error'
    BAD_GATEWAY = 'Bad Gateway'
    SERVICE_UNAVAILABLE = 'Service Unavailable'
  end

  module TestHelper
    # ============================================
    # TEST CONSTANTS
    # ============================================
    
    DEFAULT_BASE_URL = 'http://example.com'
    DEFAULT_WEBHOOK_URL = 'http://example.com/webhook'
    DEFAULT_WEBHOOK_URL_HTTPS = 'https://example.com/webhook'
    DEFAULT_WEBHOOK_SECRET = 'test_secret'
    DEFAULT_FALLBACK_SECRET = 'one_webhook_secret_key_2026'
    DEFAULT_USER_FIRSTNAME = 'Test'
    DEFAULT_USER_LASTNAME = 'User'
    DEFAULT_USER_EMAIL = 'test@example.com'
    DEFAULT_USER_PASSWORD = 'password123'
    DEFAULT_PROJECT_IDENTIFIER = 'test-project'
    DEFAULT_PROJECT_NAME = 'Test Project'
    DEFAULT_START_TIME = '17:00'
    DEFAULT_END_TIME = '19:00'
    DEFAULT_END_TIME_ALT = '19:30'
    
    # ============================================
    # PLUGIN SETTINGS HELPERS
    # ============================================
    
    def setup_plugin_settings(enabled: true, webhook_url: DEFAULT_WEBHOOK_URL, webhook_secret: DEFAULT_WEBHOOK_SECRET)
      Setting.plugin_redmine_one_webhook = {
        'enabled' => enabled ? '1' : '0',
        'webhook_url' => webhook_url,
        'webhook_secret' => webhook_secret
      }
    end
    
    def disable_plugin
      setup_plugin_settings(enabled: false)
    end
    
    def clear_plugin_settings
      Setting.plugin_redmine_one_webhook = {}
    end
    
    # ============================================
    # FACTORY METHODS
    # ============================================
    
    def create_test_user(attributes = {})
      login = attributes[:login] || "testuser_#{SecureRandom.hex(4)}"
      
      # Check if user exists by login first (login takes precedence)
      user = nil
      if attributes[:login]
        user = User.find_by(login: login)
      end
      
      # Only check by email if no login was provided AND email was provided
      if user.nil? && !attributes[:login] && attributes[:mail] && !attributes[:mail].blank?
        user = User.find_by(mail: attributes[:mail])
      end
      
      # If user exists, update and return it
      if user
        # Update existing user to ensure it's valid
        user.firstname = attributes[:firstname] || DEFAULT_USER_FIRSTNAME
        user.lastname = attributes[:lastname] || DEFAULT_USER_LASTNAME
        user.password = attributes[:password] || DEFAULT_USER_PASSWORD
        user.password_confirmation = attributes[:password] || DEFAULT_USER_PASSWORD
        user.status = User::STATUS_ACTIVE
        user.save!
        return user
      end
      
      # Create new user
      user = User.new(login: login)
      user.firstname = attributes[:firstname] || DEFAULT_USER_FIRSTNAME
      user.lastname = attributes[:lastname] || DEFAULT_USER_LASTNAME
      
      # Handle email: if explicitly set to empty/nil, use nil; otherwise use unique email
      if attributes.key?(:mail)
        if attributes[:mail].blank?
          user.mail = nil
        elsif attributes[:mail] == DEFAULT_USER_EMAIL && login.start_with?('user_no_email_')
          # Make DEFAULT_USER_EMAIL unique for auto-generated temporary users to avoid collisions
          user.mail = "#{login.gsub(/[^a-zA-Z0-9]/, '_')}@example.com"
        else
          user.mail = attributes[:mail]
        end
      else
        user.mail = "testuser_#{SecureRandom.hex(4)}@example.com"
      end
      
      user.password = attributes[:password] || DEFAULT_USER_PASSWORD
      user.password_confirmation = attributes[:password] || DEFAULT_USER_PASSWORD
      user.status = User::STATUS_ACTIVE
      
      # Save user - skip email validation only if mail is explicitly nil
      if user.mail.nil? && attributes.key?(:mail)
        # For test cases where we explicitly want no email, skip email validation
        user.save(validate: false)
      else
        user.save!
      end
      
      # Return a fresh user from database to ensure it's valid and persisted
      user.persisted? ? User.find(user.id) : user
    end
    
    def create_test_project(attributes = {})
      Project.find_or_create_by!(identifier: attributes[:identifier] || DEFAULT_PROJECT_IDENTIFIER) do |p|
        p.name = attributes[:name] || DEFAULT_PROJECT_NAME
        p.enabled_module_names = ['time_tracking']
      end
    end
    
    def create_test_issue(project, attributes = {})
      author = attributes[:author] || User.first || create_test_user
      Issue.create!(
        project: project,
        subject: attributes[:subject] || 'Test Issue',
        tracker: project.trackers.first || Tracker.first || Tracker.create!(name: 'Bug'),
        author: author,
        status: IssueStatus.first || IssueStatus.create!(name: 'New')
      )
    end
    
    def create_overtime_activity
      TimeEntryActivity.find_or_create_by!(name: 'Overtime') do |a|
        a.position = 1
        a.is_default = false
      end
    end
    
    def create_custom_fields_for_time_entry
      start_time_field = CustomField.find_or_create_by!(name: 'Start time', type: 'TimeEntryCustomField') do |cf|
        cf.field_format = 'string'
        cf.is_required = false
      end
      
      end_time_field = CustomField.find_or_create_by!(name: 'End time', type: 'TimeEntryCustomField') do |cf|
        cf.field_format = 'string'
        cf.is_required = false
      end
      
      [start_time_field, end_time_field]
    end
    
    def create_overtime_time_entry(attributes = {})
      user = attributes[:user] || create_test_user
      
      project = attributes[:project] || create_test_project
      
      # Add user as project member to allow time entry logging
      unless project.users.include?(user)
        role = Role.first || Role.create!(name: 'Test Role', permissions: [:log_time, :view_time_entries])
        Member.create!(user: user, project: project, roles: [role])
      end
      
      issue = attributes[:issue] || create_test_issue(project, author: user)
      activity = attributes[:activity] || create_overtime_activity
      
      start_time_field, end_time_field = create_custom_fields_for_time_entry
      
      time_entry = TimeEntry.new(
        project: project,
        issue: issue,
        user: user,
        activity: activity,
        hours: attributes[:hours] || 2.0,
        spent_on: attributes[:spent_on] || Date.today,
        comments: attributes[:comments] || 'Test overtime entry'
      )
      
      # Set custom field values
      time_entry.custom_field_values = {
        start_time_field.id.to_s => attributes[:start_time] || DEFAULT_START_TIME,
        end_time_field.id.to_s => attributes[:end_time] || DEFAULT_END_TIME
      }
      
      time_entry.save!
      time_entry
    end
    
    # ============================================
    # WEBHOOK SIGNATURE HELPERS
    # ============================================
    
    def generate_webhook_signature(payload_string, secret = DEFAULT_WEBHOOK_SECRET)
      require 'openssl'
      OpenSSL::HMAC.hexdigest('SHA256', secret, payload_string)
    end
    
    def verify_webhook_signature(signature, payload_string, secret = DEFAULT_WEBHOOK_SECRET)
      expected_signature = generate_webhook_signature(payload_string, secret)
      ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
    end
    
    # ============================================
    # HTTP MOCKING HELPERS
    # ============================================
    
    def stub_webhook_request(url, response_body: HttpResponseBody::OK, response_code: HttpStatus::OK, &block)
      if defined?(WebMock)
        WebMock.stub_request(:post, url).to_return(
          status: response_code,
          body: response_body,
          headers: { 'Content-Type' => 'application/json' }
        )
      else
        # Manual stubbing using Net::HTTP
        uri = URI.parse(url)
        allow(Net::HTTP).to receive(:new).and_return(mock_http_response(response_code, response_body)) if defined?(RSpec)
        # For Minitest, we'll need to use a different approach
        yield if block_given?
      end
    end
    
    def mock_http_response(code, body)
      response = double('HTTPResponse')
      allow(response).to receive(:code).and_return(code.to_s)
      allow(response).to receive(:body).and_return(body)
      http = double('Net::HTTP')
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(response)
      http
    end
    
    # ============================================
    # WAIT HELPERS (for async webhook sending)
    # ============================================
    
    def wait_for_webhook(timeout: 2)
      sleep(timeout)
    end
    
    # ============================================
    # PAYLOAD HELPERS
    # ============================================
    
    def expected_webhook_payload(time_entry, action: 'create')
      {
        event: 'overtime_sync',
        action: action,
        timestamp: anything,
        time_entry: {
          id: time_entry.id,
          hours: time_entry.hours,
          comments: time_entry.comments,
          spent_on: time_entry.spent_on.to_s,
          created_on: time_entry.created_on.iso8601,
          updated_on: time_entry.updated_on.iso8601,
          activity: {
            id: time_entry.activity.id,
            name: time_entry.activity.name
          },
          user: {
            id: time_entry.user.id,
            login: time_entry.user.login,
            firstname: time_entry.user.firstname,
            lastname: time_entry.user.lastname,
            mail: time_entry.user.mail
          },
          project: {
            id: time_entry.project.id,
            identifier: time_entry.project.identifier,
            name: time_entry.project.name
          },
          issue: time_entry.issue ? {
            id: time_entry.issue.id,
            subject: time_entry.issue.subject,
            tracker: time_entry.issue.tracker&.name
          } : nil,
          custom_field_values: array_including(
            hash_including(custom_field_name: 'Start time'),
            hash_including(custom_field_name: 'End time')
          )
        }
      }
    end
    
    # Helper for matching "anything" in assertions
    def anything
      Object.new.tap { |o| def o.===(other); true; end }
    end
    
    def array_including(*items)
      items
    end
    
    def hash_including(**keys)
      keys
    end
  end
end

# Include helper in all tests
class ActiveSupport::TestCase
  include RedmineWebhook::TestHelper
end
