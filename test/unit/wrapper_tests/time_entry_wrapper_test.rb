require File.expand_path('../../../test_helper', __FILE__)

class TimeEntryWrapperTest < ActiveSupport::TestCase
  def setup
    @user = create_test_user
    @project = create_test_project
    @issue = create_test_issue(@project)
    @activity = create_overtime_activity
    @start_field, @end_field = create_custom_fields_for_time_entry
    
    @time_entry = create_overtime_time_entry(
      user: @user,
      project: @project,
      issue: @issue,
      activity: @activity,
      hours: 2.5,
      start_time: RedmineWebhook::TestHelper::DEFAULT_START_TIME,
      end_time: RedmineWebhook::TestHelper::DEFAULT_END_TIME
    )
    
    @wrapper = RedmineWebhook::TimeEntryWrapper.new(@time_entry)
  end
  
  test "should convert time entry to hash" do
    hash = @wrapper.to_hash
    
    assert_equal @time_entry.id, hash[:id]
    assert_equal 2.5, hash[:hours]
    assert_equal @time_entry.comments, hash[:comments]
    assert_equal @time_entry.spent_on, hash[:spent_on]
    assert_not_nil hash[:created_on]
    assert_not_nil hash[:updated_on]
  end
  
  test "should include activity in hash" do
    hash = @wrapper.to_hash
    
    assert_not_nil hash[:activity]
    assert_equal @activity.id, hash[:activity][:id]
    assert_equal @activity.name, hash[:activity][:name]
  end
  
  test "should include user in hash" do
    hash = @wrapper.to_hash
    
    assert_not_nil hash[:user]
    assert_equal @user.id, hash[:user][:id]
    assert_equal @user.login, hash[:user][:login]
    assert_equal @user.firstname, hash[:user][:firstname]
    assert_equal @user.lastname, hash[:user][:lastname]
    assert_equal @user.mail, hash[:user][:mail]
  end
  
  test "should include project in hash" do
    hash = @wrapper.to_hash
    
    assert_not_nil hash[:project]
    assert_equal @project.id, hash[:project][:id]
    assert_equal @project.identifier, hash[:project][:identifier]
    assert_equal @project.name, hash[:project][:name]
  end
  
  test "should include issue in hash" do
    hash = @wrapper.to_hash
    
    assert_not_nil hash[:issue]
    assert_equal @issue.id, hash[:issue][:id]
    assert_equal @issue.subject, hash[:issue][:subject]
  end
  
  test "should include custom field values in hash" do
    hash = @wrapper.to_hash
    
    assert_not_nil hash[:custom_field_values]
    assert hash[:custom_field_values].is_a?(Array)
    assert hash[:custom_field_values].any? { |cfv| cfv[:custom_field_name] == 'Start time' }
    assert hash[:custom_field_values].any? { |cfv| cfv[:custom_field_name] == 'End time' }
  end
  
  test "should handle time entry without issue" do
    time_entry = create_overtime_time_entry
    time_entry.update_column(:issue_id, nil)
    time_entry.reload
    
    wrapper = RedmineWebhook::TimeEntryWrapper.new(time_entry)
    hash = wrapper.to_hash
    
    assert_nil hash[:issue]
  end
  
  test "should handle time entry without activity" do
    skip "Cannot test nil activity_id - database has NOT NULL constraint"
    time_entry = create_overtime_time_entry
    time_entry.update_column(:activity_id, nil)
    time_entry.reload
    
    wrapper = RedmineWebhook::TimeEntryWrapper.new(time_entry)
    hash = wrapper.to_hash
    
    assert_nil hash[:activity]
  end
  
  test "should handle empty custom field values" do
    time_entry = TimeEntry.create!(
      project: @project,
      issue: @issue,
      user: @user,
      activity: @activity,
      hours: 2.0,
      spent_on: Date.today
    )
    
    wrapper = RedmineWebhook::TimeEntryWrapper.new(time_entry)
    hash = wrapper.to_hash
    
    assert_equal [], hash[:custom_field_values]
  end
end
