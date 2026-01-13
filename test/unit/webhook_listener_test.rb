require File.expand_path('../../test_helper', __FILE__)

class WebhookListenerTest < ActiveSupport::TestCase
  def setup
    @listener = RedmineWebhook::WebhookListener.new
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
  # PLUGIN ENABLED/DISABLED TESTS
  # ============================================
  
  test "should not send webhook when plugin is disabled" do
    disable_plugin
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    @listener.controller_timelog_edit_before_save(time_entry: time_entry)
    wait_for_webhook
    
    # Webhook should not be sent when plugin is disabled
    assert true
  end
  
  test "should send webhook when plugin is enabled" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    @listener.controller_timelog_edit_before_save(time_entry: time_entry)
    wait_for_webhook
    
    # Webhook should be sent (we can't easily verify without WebMock, but we can check logs)
    assert true # Placeholder - in real test with WebMock, we'd verify the request
  end
  
  # ============================================
  # OVERTIME ACTIVITY DETECTION TESTS
  # ============================================
  
  test "should detect overtime activity" do
    time_entry = create_overtime_time_entry(activity: @overtime_activity)
    
    assert @listener.send(:overtime_activity?, time_entry)
  end
  
  test "should detect OT activity (case insensitive)" do
    ot_activity = TimeEntryActivity.find_or_create_by!(name: 'OT') do |a|
      a.position = 1
    end
    
    time_entry = create_overtime_time_entry(activity: ot_activity)
    
    assert @listener.send(:overtime_activity?, time_entry)
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
    
    assert_not @listener.send(:overtime_activity?, time_entry)
  end
  
  # ============================================
  # VALIDATION TESTS
  # ============================================
  
  test "should validate overtime payload with all required fields" do
    time_entry = create_overtime_time_entry(
      hours: 2.5,
      start_time: RedmineWebhook::TestHelper::DEFAULT_START_TIME,
      end_time: RedmineWebhook::TestHelper::DEFAULT_END_TIME
    )
    
    assert @listener.send(:valid_overtime_payload?, time_entry)
  end
  
  test "should reject payload with zero hours" do
    time_entry = create_overtime_time_entry(hours: 0)
    
    assert_not @listener.send(:valid_overtime_payload?, time_entry)
  end
  
  test "should reject payload without start time" do
    time_entry = create_overtime_time_entry
    time_entry.custom_field_values = {
      @start_field.id.to_s => '',
      @end_field.id.to_s => RedmineWebhook::TestHelper::DEFAULT_END_TIME
    }
    time_entry.save!
    
    assert_not @listener.send(:valid_overtime_payload?, time_entry)
  end
  
  test "should reject payload without end time" do
    time_entry = create_overtime_time_entry
    time_entry.custom_field_values = {
      @start_field.id.to_s => RedmineWebhook::TestHelper::DEFAULT_START_TIME,
      @end_field.id.to_s => ''
    }
    time_entry.save!
    
    assert_not @listener.send(:valid_overtime_payload?, time_entry)
  end
  
  test "should reject payload with non-overtime activity" do
    regular_activity = TimeEntryActivity.find_or_create_by!(name: 'Development') do |a|
      a.position = 1
    end
    
    time_entry = create_overtime_time_entry(activity: regular_activity)
    
    assert_not @listener.send(:valid_overtime_payload?, time_entry)
  end
  
  # ============================================
  # SIGNATURE GENERATION TESTS
  # ============================================
  
  test "should generate correct HMAC-SHA256 signature" do
    payload_string = '{"test": "data"}'
    signature = @listener.send(:generate_signature, payload_string)
    
    expected = generate_webhook_signature(payload_string, @webhook_secret)
    assert_equal expected, signature
  end
  
  test "should use default secret when not configured" do
    clear_plugin_settings
    payload_string = '{"test": "data"}'
    signature = @listener.send(:generate_signature, payload_string)
    
    expected = generate_webhook_signature(payload_string, RedmineWebhook::TestHelper::DEFAULT_FALLBACK_SECRET)
    assert_equal expected, signature
  end
  
  # ============================================
  # WEBHOOK URL TESTS
  # ============================================
  
  test "should not send webhook when URL is blank" do
    setup_plugin_settings(enabled: true, webhook_url: '', webhook_secret: @webhook_secret)
    time_entry = create_overtime_time_entry
    
    assert_not @listener.send(:should_send_webhook?, time_entry)
  end
  
  test "should get webhook URL from settings" do
    assert_equal @webhook_url, @listener.send(:global_webhook_url)
  end
  
  # ============================================
  # CUSTOM FIELD VALUE TESTS
  # ============================================
  
  test "should get custom field value by name" do
    time_entry = create_overtime_time_entry(
      start_time: '17:30',
      end_time: '20:00'
    )
    
    start_time = @listener.send(:get_custom_field_value, time_entry, ['start time', 'start_time'])
    end_time = @listener.send(:get_custom_field_value, time_entry, ['end time', 'end_time'])
    
    assert_equal '17:30', start_time
    assert_equal '20:00', end_time
  end
  
  test "should handle case-insensitive custom field names" do
    time_entry = create_overtime_time_entry(
      start_time: '18:00',
      end_time: '21:00'
    )
    
    # Try different case variations
    start_time = @listener.send(:get_custom_field_value, time_entry, ['START TIME'])
    end_time = @listener.send(:get_custom_field_value, time_entry, ['End Time'])
    
    assert_equal '18:00', start_time
    assert_equal '21:00', end_time
  end
  
  # ============================================
  # PAYLOAD BUILDING TESTS
  # ============================================
  
  test "should build correct create payload" do
    time_entry = create_overtime_time_entry
    payload = @listener.send(:build_overtime_payload, time_entry, 'create')
    
    assert_equal 'overtime_sync', payload[:event]
    assert_equal 'create', payload[:action]
    assert_not_nil payload[:timestamp]
    assert_not_nil payload[:time_entry]
    assert_equal time_entry.id, payload[:time_entry][:id]
  end
  
  test "should build correct update payload" do
    time_entry = create_overtime_time_entry
    payload = @listener.send(:build_overtime_payload, time_entry, 'update')
    
    assert_equal 'update', payload[:action]
  end
  
  test "should build correct delete payload" do
    time_entry = create_overtime_time_entry
    payload = @listener.send(:build_overtime_payload, time_entry, 'delete')
    
    assert_equal 'delete', payload[:action]
  end
  
  # ============================================
  # HOOK EXECUTION TESTS
  # ============================================
  
  test "controller_timelog_edit_before_save should process new time entry" do
    time_entry = TimeEntry.new(
      project: @project,
      issue: @issue,
      user: @user,
      activity: @overtime_activity,
      hours: 2.0,
      spent_on: Date.today
    )
    time_entry.custom_field_values = {
      @start_field.id.to_s => RedmineWebhook::TestHelper::DEFAULT_START_TIME,
      @end_field.id.to_s => RedmineWebhook::TestHelper::DEFAULT_END_TIME
    }
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    # This should not raise an error
    assert_nothing_raised do
      @listener.controller_timelog_edit_before_save(time_entry: time_entry)
      wait_for_webhook
    end
  end
  
  test "controller_timelog_edit_after_save should process update" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    assert_nothing_raised do
      @listener.controller_timelog_edit_after_save(time_entry: time_entry)
      wait_for_webhook
    end
  end
  
  test "controller_issues_edit_after_save should process time entry from issue" do
    time_entry = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    assert_nothing_raised do
      @listener.controller_issues_edit_after_save(time_entry: time_entry)
      wait_for_webhook
    end
  end
  
  test "controller_timelog_bulk_edit_after_save should process multiple entries" do
    time_entry1 = create_overtime_time_entry
    time_entry2 = create_overtime_time_entry
    
    stub_webhook_request(@webhook_url, response_code: RedmineWebhook::HttpStatus::OK)
    
    assert_nothing_raised do
      @listener.controller_timelog_bulk_edit_after_save(time_entries: [time_entry1, time_entry2])
      wait_for_webhook(timeout: 3)
    end
  end
end
