require File.expand_path('../../../test_helper', __FILE__)

class IssueWrapperTest < ActiveSupport::TestCase
  def setup
    @user = create_test_user
    @project = create_test_project
    @issue = create_test_issue(@project, subject: 'Test Issue')
  end
  
  test "should convert issue to hash" do
    wrapper = RedmineWebhook::IssueWrapper.new(@issue)
    hash = wrapper.to_hash
    
    assert_equal @issue.id, hash[:id]
    assert_equal 'Test Issue', hash[:subject]
    assert_equal @issue.description, hash[:description]
    assert_not_nil hash[:created_on]
    assert_not_nil hash[:updated_on]
  end
  
  test "should include project in hash" do
    wrapper = RedmineWebhook::IssueWrapper.new(@issue)
    hash = wrapper.to_hash
    
    assert_not_nil hash[:project]
    assert_equal @project.id, hash[:project][:id]
  end
  
  test "should include status in hash" do
    wrapper = RedmineWebhook::IssueWrapper.new(@issue)
    hash = wrapper.to_hash
    
    assert_not_nil hash[:status]
  end
  
  test "should include tracker in hash" do
    wrapper = RedmineWebhook::IssueWrapper.new(@issue)
    hash = wrapper.to_hash
    
    assert_not_nil hash[:tracker]
  end
  
  test "should include author in hash" do
    wrapper = RedmineWebhook::IssueWrapper.new(@issue)
    hash = wrapper.to_hash
    
    assert_not_nil hash[:author]
  end
  
  test "should include custom field values" do
    wrapper = RedmineWebhook::IssueWrapper.new(@issue)
    hash = wrapper.to_hash
    
    assert_not_nil hash[:custom_field_values]
    assert hash[:custom_field_values].is_a?(Array)
  end
end
