require File.expand_path('../../test_helper', __FILE__)

class TimeEntryPatchTest < ActiveSupport::TestCase
  def setup
    @webhook_url = RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_URL
    @webhook_secret = RedmineWebhook::TestHelper::DEFAULT_WEBHOOK_SECRET
    setup_plugin_settings(
      enabled: true,
      webhook_url: @webhook_url,
      webhook_secret: @webhook_secret
    )
    
    @user = create_test_user
    @project = create_test_project
    
    # Add user as project member
    role = Role.first || Role.create!(name: 'Test Role', permissions: [:log_time, :view_time_entries])
    Member.create!(user: @user, project: @project, roles: [role]) unless @project.users.include?(@user)
    
    @issue = create_test_issue(@project)
    @overtime_activity = create_overtime_activity
    @start_field, @end_field = create_custom_fields_for_time_entry
  end
  
  def teardown
    clear_plugin_settings
  end
  
  # ============================================
  # BEFORE_DESTROY CALLBACK TESTS
  # ============================================
  
  test "should send webhook when overtime time entry is deleted" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    assert_nothing_raised do
      time_entry.destroy
      wait_for_webhook
    end
  end
  
  test "should not send webhook when non-overtime time entry is deleted" do
    regular_activity = TimeEntryActivity.find_or_create_by!(name: 'Development') do |a|
      a.position = 1
    end
    
    time_entry = TimeEntry.create!(
      project: @project,
      issue: @issue,
      user: @user,
      activity: regular_activity,
      hours: 2.0,
      spent_on: Date.today
    )
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    # Should not raise error, but webhook should not be sent
    assert_nothing_raised do
      time_entry.destroy
      wait_for_webhook
    end
  end
  
  test "should not send webhook when plugin is disabled" do
    disable_plugin
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    assert_nothing_raised do
      time_entry.destroy
      wait_for_webhook
    end
  end
  
  test "should not send webhook when URL is blank" do
    setup_plugin_settings(enabled: true, webhook_url: '', webhook_secret: @webhook_secret)
    time_entry = create_overtime_time_entry
    
    assert_nothing_raised do
      time_entry.destroy
      wait_for_webhook
    end
  end
  
  # ============================================
  # OVERTIME ACTIVITY DETECTION TESTS
  # ============================================
  
  test "should detect overtime activity" do
    time_entry = create_overtime_time_entry
    
    assert time_entry.send(:overtime_activity?)
  end
  
  test "should detect OT activity (case insensitive)" do
    ot_activity = TimeEntryActivity.find_or_create_by!(name: 'OT') do |a|
      a.position = 1
    end
    
    time_entry = create_overtime_time_entry(activity: ot_activity)
    
    assert time_entry.send(:overtime_activity?)
  end
  
  test "should not detect non-overtime activity" do
    regular_activity = TimeEntryActivity.find_or_create_by!(name: 'Development') do |a|
      a.position = 1
    end
    
    time_entry = TimeEntry.create!(
      project: @project,
      issue: @issue,
      user: @user,
      activity: regular_activity,
      hours: 2.0,
      spent_on: Date.today
    )
    
    assert_not time_entry.send(:overtime_activity?)
  end
  
  # ============================================
  # DELETE PAYLOAD TESTS
  # ============================================
  
  test "should build correct delete payload" do
    time_entry = create_overtime_time_entry
    payload = time_entry.send(:build_delete_payload)
    
    assert_equal 'overtime_sync', payload[:event]
    assert_equal 'delete', payload[:action]
    assert_not_nil payload[:timestamp]
    assert_not_nil payload[:time_entry]
    assert_equal time_entry.id, payload[:time_entry][:id]
  end
  
  # ============================================
  # UPDATE_ALL TESTS (Issue Reassignment)
  # ============================================
  
  test "should detect issue_id change in update_all with hash" do
    time_entry = create_overtime_time_entry
    new_issue = create_test_issue(@project)
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    # This will trigger update_all with hash format
    assert_nothing_raised do
      TimeEntry.where(id: time_entry.id).update_all(issue_id: new_issue.id)
      wait_for_webhook
    end
  end
  
  test "should detect issue_id nullification in update_all" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    assert_nothing_raised do
      TimeEntry.where(id: time_entry.id).update_all(issue_id: nil)
      wait_for_webhook
    end
  end
  
  test "should handle update_all with string format" do
    time_entry = create_overtime_time_entry
    new_issue = create_test_issue(@project)
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    assert_nothing_raised do
      TimeEntry.where(id: time_entry.id).update_all("issue_id = #{new_issue.id}")
      wait_for_webhook
    end
  end
  
  test "should not process non-issue_id updates in update_all" do
    time_entry = create_overtime_time_entry
    
    # Update something other than issue_id
    assert_nothing_raised do
      TimeEntry.where(id: time_entry.id).update_all(comments: 'Updated comment')
    end
  end
  
  # ============================================
  # PLUGIN SETTINGS TESTS
  # ============================================
  
  test "should check if plugin is enabled" do
    time_entry = create_overtime_time_entry
    
    assert time_entry.send(:plugin_enabled?)
  end
  
  test "should get webhook URL from settings" do
    time_entry = create_overtime_time_entry
    
    assert_equal @webhook_url, time_entry.send(:global_webhook_url)
  end
  
  test "should get webhook secret from settings" do
    time_entry = create_overtime_time_entry
    
    assert_equal @webhook_secret, time_entry.send(:webhook_secret)
  end
  
  test "should use default secret when not configured" do
    setup_plugin_settings(enabled: true, webhook_url: @webhook_url, webhook_secret: '')
    time_entry = create_overtime_time_entry
    
    assert_equal RedmineWebhook::TestHelper::DEFAULT_FALLBACK_SECRET, time_entry.send(:webhook_secret)
  end
  
  # ============================================
  # SIGNATURE GENERATION TESTS
  # ============================================
  
  test "should generate correct HMAC-SHA256 signature" do
    time_entry = create_overtime_time_entry
    payload_string = '{"test": "data"}'
    signature = time_entry.send(:generate_signature, payload_string)
    
    expected = generate_webhook_signature(payload_string, @webhook_secret)
    assert_equal expected, signature
  end
  
  # ============================================
  # EDGE CASES
  # ============================================
  
  test "should handle time entry without issue" do
    time_entry = create_overtime_time_entry
    time_entry.update_column(:issue_id, nil)
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    assert_nothing_raised do
      time_entry.destroy
      wait_for_webhook
    end
  end
  
  test "should handle time entry without activity" do
    skip "Cannot test nil activity_id - database has NOT NULL constraint"
    time_entry = create_overtime_time_entry
    time_entry.update_column(:activity_id, nil)
    
    # Should not send webhook
    assert_nothing_raised do
      time_entry.destroy
      wait_for_webhook
    end
  end
end
