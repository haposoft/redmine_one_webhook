require File.expand_path('../../../test_helper', __FILE__)

class CustomFieldValueWrapperTest < ActiveSupport::TestCase
  def setup
    @start_field, @end_field = create_custom_fields_for_time_entry
    @time_entry = create_overtime_time_entry(
      start_time: RedmineWebhook::TestHelper::DEFAULT_START_TIME,
      end_time: RedmineWebhook::TestHelper::DEFAULT_END_TIME
    )
    
    @custom_field_value = @time_entry.custom_field_values.find { |cfv| cfv.custom_field_id == @start_field.id }
  end
  
  test "should convert custom field value to hash" do
    wrapper = RedmineWebhook::CustomFieldValueWrapper.new(@custom_field_value)
    hash = wrapper.to_hash
    
    assert_equal @start_field.id, hash[:custom_field_id]
    assert_equal 'Start time', hash[:custom_field_name]
    assert_equal RedmineWebhook::TestHelper::DEFAULT_START_TIME, hash[:value]
  end
  
  test "should handle different custom field types" do
    end_cfv = @time_entry.custom_field_values.find { |cfv| cfv.custom_field_id == @end_field.id }
    wrapper = RedmineWebhook::CustomFieldValueWrapper.new(end_cfv)
    hash = wrapper.to_hash
    
    assert_equal @end_field.id, hash[:custom_field_id]
    assert_equal 'End time', hash[:custom_field_name]
    assert_equal RedmineWebhook::TestHelper::DEFAULT_END_TIME, hash[:value]
  end
end
