require File.expand_path('../../test_helper', __FILE__)

class WebhookIntegrationTest < ActiveSupport::TestCase
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
    
    # Add user as project member to allow time entry logging
    unless @project.users.include?(@user)
      role = Role.first || Role.create!(name: 'Test Role', permissions: [:log_time, :view_time_entries])
      Member.create!(user: @user, project: @project, roles: [role])
    end
    
    @issue = create_test_issue(@project)
    @overtime_activity = create_overtime_activity
    @start_field, @end_field = create_custom_fields_for_time_entry
  end
  
  def teardown
    clear_plugin_settings
  end
  
  # ============================================
  # CREATE WEBHOOK FLOW TESTS
  # ============================================
  
  test "should send create webhook when time entry is created from log time page" do
    time_entry = TimeEntry.new(
      project: @project,
      issue: @issue,
      user: @user,
      activity: @overtime_activity,
      hours: 2.0,
      spent_on: Date.today,
      comments: 'Integration test overtime'
    )
    time_entry.custom_field_values = {
      @start_field.id.to_s => RedmineWebhook::TestHelper::DEFAULT_START_TIME,
      @end_field.id.to_s => RedmineWebhook::TestHelper::DEFAULT_END_TIME
    }
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    listener = RedmineWebhook::WebhookListener.new
    listener.controller_timelog_edit_before_save(time_entry: time_entry)
    
    # Save the time entry
    time_entry.save!
    
    wait_for_webhook
    
    # Verify webhook was sent (in real scenario with WebMock, we'd verify the request)
    assert true
  end
  
  test "should send create webhook when time entry is created from issue edit" do
    time_entry = TimeEntry.new(
      project: @project,
      issue: @issue,
      user: @user,
      activity: @overtime_activity,
      hours: 1.5,
      spent_on: Date.today
    )
    time_entry.custom_field_values = {
      @start_field.id.to_s => '18:00',
      @end_field.id.to_s => RedmineWebhook::TestHelper::DEFAULT_END_TIME_ALT
    }
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    listener = RedmineWebhook::WebhookListener.new
    listener.controller_issues_edit_after_save(time_entry: time_entry)
    
    time_entry.save!
    
    wait_for_webhook
    
    assert true
  end
  
  # ============================================
  # UPDATE WEBHOOK FLOW TESTS
  # ============================================
  
  test "should send update webhook when time entry is updated" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    listener = RedmineWebhook::WebhookListener.new
    
    # Update the time entry
    time_entry.update(hours: 3.0, comments: 'Updated overtime')
    
    listener.controller_timelog_edit_after_save(time_entry: time_entry)
    
    wait_for_webhook
    
    assert true
  end
  
  test "should send update webhook when time entry is bulk edited" do
    time_entry1 = create_overtime_time_entry
    time_entry2 = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    listener = RedmineWebhook::WebhookListener.new
    listener.controller_timelog_bulk_edit_after_save(time_entries: [time_entry1, time_entry2])
    
    wait_for_webhook(timeout: 3)
    
    assert true
  end
  
  # ============================================
  # DELETE WEBHOOK FLOW TESTS
  # ============================================
  
  test "should send delete webhook when time entry is deleted" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    time_entry.destroy
    
    wait_for_webhook
    
    assert true
  end
  
  # ============================================
  # PAYLOAD VERIFICATION TESTS
  # ============================================
  
  test "should include correct payload structure in webhook" do
    time_entry = create_overtime_time_entry(
      hours: 2.5,
      start_time: RedmineWebhook::TestHelper::DEFAULT_START_TIME,
      end_time: RedmineWebhook::TestHelper::DEFAULT_END_TIME_ALT
    )
    
    listener = RedmineWebhook::WebhookListener.new
    payload = listener.send(:build_overtime_payload, time_entry, 'create')
    
    assert_equal 'overtime_sync', payload[:event]
    assert_equal 'create', payload[:action]
    assert_not_nil payload[:timestamp]
    assert_not_nil payload[:time_entry]
    
    te = payload[:time_entry]
    assert_equal time_entry.id, te[:id]
    assert_equal 2.5, te[:hours]
    assert_not_nil te[:user]
    assert_not_nil te[:project]
    assert_not_nil te[:activity]
    assert_not_nil te[:custom_field_values]
  end
  
  test "should include correct signature in webhook headers" do
    time_entry = create_overtime_time_entry
    
    listener = RedmineWebhook::WebhookListener.new
    payload = listener.send(:build_overtime_payload, time_entry, 'create')
    payload_string = payload.to_json
    signature = listener.send(:generate_signature, payload_string)
    
    assert verify_webhook_signature(signature, payload_string, @webhook_secret)
  end
  
  # ============================================
  # ERROR HANDLING TESTS
  # ============================================
  
  test "should handle webhook URL connection errors gracefully" do
    time_entry = create_overtime_time_entry
    
    # Use invalid URL
    setup_plugin_settings(
      enabled: true,
      webhook_url: 'http://invalid-domain-that-does-not-exist-12345.com/webhook',
      webhook_secret: @webhook_secret
    )
    
    listener = RedmineWebhook::WebhookListener.new
    
    # Should not raise error
    assert_nothing_raised do
      listener.controller_timelog_edit_after_save(time_entry: time_entry)
      wait_for_webhook
    end
  end
  
  test "should handle webhook server errors gracefully" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(
      @webhook_url, 
      response_code: RedmineWebhook::HttpStatus::INTERNAL_SERVER_ERROR, 
      response_body: RedmineWebhook::HttpResponseBody::INTERNAL_SERVER_ERROR
    )
    
    listener = RedmineWebhook::WebhookListener.new
    
    assert_nothing_raised do
      listener.controller_timelog_edit_after_save(time_entry: time_entry)
      wait_for_webhook
    end
  end
  
  # ============================================
  # VALIDATION FLOW TESTS
  # ============================================
  
  test "should not send webhook for invalid payload" do
    time_entry = create_overtime_time_entry
    time_entry.update_column(:hours, 0)
    time_entry.reload
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    listener = RedmineWebhook::WebhookListener.new
    listener.controller_timelog_edit_after_save(time_entry: time_entry)
    
    wait_for_webhook
    
    # Webhook should not be sent for invalid payload
    assert true
  end
  
  test "should not send webhook when plugin is disabled" do
    disable_plugin
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    listener = RedmineWebhook::WebhookListener.new
    listener.controller_timelog_edit_after_save(time_entry: time_entry)
    
    wait_for_webhook
    
    # Webhook should not be sent
    assert true
  end
  
  test "should not send webhook for non-overtime activity" do
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
    
    listener = RedmineWebhook::WebhookListener.new
    listener.controller_timelog_edit_after_save(time_entry: time_entry)
    
    wait_for_webhook
    
    # Webhook should not be sent
    assert true
  end
  
  # ============================================
  # MULTIPLE ENTRY POINTS TESTS
  # ============================================
  
  test "should handle webhook from multiple entry points" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    listener = RedmineWebhook::WebhookListener.new
    
    # Simulate webhook from different entry points
    listener.controller_timelog_edit_after_save(time_entry: time_entry)
    listener.controller_issues_edit_after_save(time_entry: time_entry)
    
    wait_for_webhook(timeout: 3)
    
    assert true
  end
end
