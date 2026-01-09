require File.expand_path('../../test_helper', __FILE__)

class SettingsTest < ActiveSupport::TestCase
  def setup
    clear_plugin_settings
  end
  
  def teardown
    clear_plugin_settings
  end
  
  # ============================================
  # DEFAULT SETTINGS TESTS
  # ============================================
  
  test "should have default settings" do
    # Defaults are set in init.rb
    settings = Setting.plugin_redmine_one_webhook
    
    # After plugin registration, defaults should be available
    assert_not_nil settings
  end
  
  test "should have default webhook secret" do
    setup_plugin_settings(enabled: true, webhook_url: 'http://test.com', webhook_secret: '')
    
    listener = RedmineWebhook::WebhookListener.new
    secret = listener.send(:webhook_secret)
    
    assert_equal RedmineWebhook::TestHelper::DEFAULT_FALLBACK_SECRET, secret
  end
  
  # ============================================
  # SETTINGS VALIDATION TESTS
  # ============================================
  
  test "should accept valid webhook URL" do
    setup_plugin_settings(
      enabled: true,
      webhook_url: RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_URL,
      webhook_secret: RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_SECRET
    )
    
    listener = RedmineWebhook::WebhookListener.new
    url = listener.send(:global_webhook_url)
    
    assert_equal RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_URL, url
  end
  
  test "should accept HTTPS webhook URL" do
    setup_plugin_settings(
      enabled: true,
      webhook_url: RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_URL_HTTPS,
      webhook_secret: RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_SECRET
    )
    
    listener = RedmineWebhook::WebhookListener.new
    url = listener.send(:global_webhook_url)
    
    assert_equal RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_URL_HTTPS, url
  end
  
  test "should handle empty webhook URL" do
    setup_plugin_settings(
      enabled: true,
      webhook_url: '',
      webhook_secret: RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_SECRET
    )
    
    listener = RedmineWebhook::WebhookListener.new
    url = listener.send(:global_webhook_url)
    
    assert_equal '', url
  end
  
  test "should handle whitespace in webhook URL" do
    setup_plugin_settings(
      enabled: true,
      webhook_url: "  #{RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_URL}  ",
      webhook_secret: RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_SECRET
    )
    
    listener = RedmineWebhook::WebhookListener.new
    url = listener.send(:global_webhook_url)
    
    assert_equal RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_URL, url
  end
  
  # ============================================
  # ENABLED/DISABLED TESTS
  # ============================================
  
  test "should check if plugin is enabled" do
    setup_plugin_settings(enabled: true)
    
    listener = RedmineWebhook::WebhookListener.new
    assert listener.send(:plugin_enabled?)
  end
  
  test "should check if plugin is disabled" do
    setup_plugin_settings(enabled: false)
    
    listener = RedmineWebhook::WebhookListener.new
    assert_not listener.send(:plugin_enabled?)
  end
  
  test "should treat missing enabled setting as disabled" do
    Setting.plugin_redmine_one_webhook = {
      'webhook_url' => RedmineWebhook::TestHelper::DEFAULT_BASE_URL,
      'webhook_secret' => 'secret'
    }
    
    listener = RedmineWebhook::WebhookListener.new
    assert_not listener.send(:plugin_enabled?)
  end
  
  # ============================================
  # SECRET KEY TESTS
  # ============================================
  
  test "should use configured secret key" do
    custom_secret = 'my_custom_secret_123'
    setup_plugin_settings(
      enabled: true,
      webhook_url: RedmineWebhook::TestHelper::DEFAULT_BASE_URL,
      webhook_secret: custom_secret
    )
    
    listener = RedmineWebhook::WebhookListener.new
    secret = listener.send(:webhook_secret)
    
    assert_equal custom_secret, secret
  end
  
  test "should use default secret when not configured" do
    setup_plugin_settings(
      enabled: true,
      webhook_url: RedmineWebhook::TestHelper::DEFAULT_BASE_URL,
      webhook_secret: ''
    )
    
    listener = RedmineWebhook::WebhookListener.new
    secret = listener.send(:webhook_secret)
    
    assert_equal RedmineWebhook::TestHelper::DEFAULT_FALLBACK_SECRET, secret
  end
  
  test "should handle whitespace in secret key" do
    setup_plugin_settings(
      enabled: true,
      webhook_url: RedmineWebhook::TestHelper::DEFAULT_BASE_URL,
      webhook_secret: "  #{RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_SECRET}  "
    )
    
    listener = RedmineWebhook::WebhookListener.new
    secret = listener.send(:webhook_secret)
    
    assert_equal RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_SECRET, secret
  end
  
  # ============================================
  # SETTINGS PERSISTENCE TESTS
  # ============================================
  
  test "should persist settings" do
    setup_plugin_settings(
      enabled: true,
      webhook_url: 'http://test.com/webhook',
      webhook_secret: 'persisted_secret'
    )
    
    # Reload settings
    settings = Setting.plugin_redmine_one_webhook
    
    assert_equal '1', settings['enabled']
    assert_equal 'http://test.com/webhook', settings['webhook_url']
    assert_equal 'persisted_secret', settings['webhook_secret']
  end
  
  # ============================================
  # EDGE CASES
  # ============================================
  
  test "should handle nil settings gracefully" do
    Setting.plugin_redmine_one_webhook = nil
    
    listener = RedmineWebhook::WebhookListener.new
    
    assert_not listener.send(:plugin_enabled?)
    assert_equal '', listener.send(:global_webhook_url)
    assert_equal RedmineWebhook::TestHelper::DEFAULT_FALLBACK_SECRET, listener.send(:webhook_secret)
  end
  
  test "should handle missing settings keys" do
    Setting.plugin_redmine_one_webhook = {}
    
    listener = RedmineWebhook::WebhookListener.new
    
    assert_not listener.send(:plugin_enabled?)
    assert_equal '', listener.send(:global_webhook_url)
    assert_equal RedmineWebhook::TestHelper::DEFAULT_FALLBACK_SECRET, listener.send(:webhook_secret)
  end
end
