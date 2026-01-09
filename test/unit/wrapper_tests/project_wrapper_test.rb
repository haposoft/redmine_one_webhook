require File.expand_path('../../../test_helper', __FILE__)

class ProjectWrapperTest < ActiveSupport::TestCase
  def setup
    @project = create_test_project(
      identifier: RedmineWebhook::TestHelper::DEFAULT_PROJECT_IDENTIFIER,
      name: RedmineWebhook::TestHelper::DEFAULT_PROJECT_NAME
    )
  end
  
  test "should convert project to hash" do
    wrapper = RedmineWebhook::ProjectWrapper.new(@project)
    hash = wrapper.to_hash
    
    assert_equal @project.id, hash[:id]
    assert_equal RedmineWebhook::TestHelper::DEFAULT_PROJECT_IDENTIFIER, hash[:identifier]
    assert_equal RedmineWebhook::TestHelper::DEFAULT_PROJECT_NAME, hash[:name]
    assert_equal @project.description, hash[:description]
    assert_not_nil hash[:created_on]
  end
  
  test "should include homepage if present" do
    @project.update_column(:homepage, RedmineWebhook::TestHelper::DEFAULT_BASE_URL)
    @project.reload
    
    wrapper = RedmineWebhook::ProjectWrapper.new(@project)
    hash = wrapper.to_hash
    
    assert_equal RedmineWebhook::TestHelper::DEFAULT_BASE_URL, hash[:homepage]
  end
end
