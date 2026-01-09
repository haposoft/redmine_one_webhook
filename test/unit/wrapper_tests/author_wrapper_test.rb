require File.expand_path('../../../test_helper', __FILE__)
require 'securerandom'

class AuthorWrapperTest < ActiveSupport::TestCase
  def setup
    @user = create_test_user(
      login: 'testuser',
      firstname: RedmineWebhook::TestHelper::DEFAULT_USER_FIRSTNAME,
      lastname: RedmineWebhook::TestHelper::DEFAULT_USER_LASTNAME,
      mail: RedmineWebhook::TestHelper::DEFAULT_USER_EMAIL
    )
  end
  
  test "should convert user to hash" do
    wrapper = RedmineWebhook::AuthorWrapper.new(@user)
    hash = wrapper.to_hash
    
    assert_equal @user.id, hash[:id]
    assert_equal 'testuser', hash[:login]
    assert_equal RedmineWebhook::TestHelper::DEFAULT_USER_EMAIL, hash[:mail]
    assert_equal RedmineWebhook::TestHelper::DEFAULT_USER_FIRSTNAME, hash[:firstname]
    assert_equal RedmineWebhook::TestHelper::DEFAULT_USER_LASTNAME, hash[:lastname]
  end
  
  test "should return nil for nil author" do
    wrapper = RedmineWebhook::AuthorWrapper.new(nil)
    hash = wrapper.to_hash
    
    assert_nil hash
  end
  
  test "should include icon_url when user has email" do
    wrapper = RedmineWebhook::AuthorWrapper.new(@user)
    hash = wrapper.to_hash
    
    assert_not_nil hash[:icon_url]
  end
  
  test "should handle user without email" do
    # Create user with email first, then remove it for testing
    user = create_test_user(login: "user_no_email_#{SecureRandom.hex(4)}", mail: RedmineWebhook::TestHelper::DEFAULT_USER_EMAIL)
    user.mail = nil
    user.save(validate: false)
    user.reload
    
    wrapper = RedmineWebhook::AuthorWrapper.new(user)
    hash = wrapper.to_hash
    
    assert_nil hash[:icon_url]
  end
end
