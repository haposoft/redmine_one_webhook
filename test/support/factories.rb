module RedmineWebhook
  module Factories
    # Factory methods for creating test data
    # These are convenience methods that wrap the TestHelper methods
    
    def self.create_user(attributes = {})
      User.find_or_create_by!(login: attributes[:login] || "user_#{SecureRandom.hex(4)}") do |u|
        u.firstname = attributes[:firstname] || RedmineWebhook::TestHelper::DEFAULT_USER_FIRSTNAME
        u.lastname = attributes[:lastname] || RedmineWebhook::TestHelper::DEFAULT_USER_LASTNAME
        u.mail = attributes[:mail] || "test_#{SecureRandom.hex(4)}@example.com"
        u.password = attributes[:password] || RedmineWebhook::TestHelper::DEFAULT_USER_PASSWORD
        u.password_confirmation = attributes[:password] || RedmineWebhook::TestHelper::DEFAULT_USER_PASSWORD
        u.status = User::STATUS_ACTIVE
      end
    end
    
    def self.create_project(attributes = {})
      identifier = attributes[:identifier] || "project_#{SecureRandom.hex(4)}"
      Project.find_or_create_by!(identifier: identifier) do |p|
        p.name = attributes[:name] || RedmineWebhook::TestHelper::DEFAULT_PROJECT_NAME
        p.enabled_module_names = ['time_tracking']
      end
    end
    
    def self.create_issue(project, attributes = {})
      Issue.create!(
        project: project,
        subject: attributes[:subject] || 'Test Issue',
        tracker: project.trackers.first || Tracker.first || Tracker.create!(name: 'Bug'),
        author: attributes[:author] || User.first || create_user,
        status: IssueStatus.first || IssueStatus.create!(name: 'New')
      )
    end
    
    def self.create_overtime_activity
      TimeEntryActivity.find_or_create_by!(name: 'Overtime') do |a|
        a.position = 1
        a.is_default = false
      end
    end
    
    def self.create_custom_fields
      start_time = CustomField.find_or_create_by!(name: 'Start time', type: 'TimeEntryCustomField') do |cf|
        cf.field_format = 'string'
        cf.is_required = false
      end
      
      end_time = CustomField.find_or_create_by!(name: 'End time', type: 'TimeEntryCustomField') do |cf|
        cf.field_format = 'string'
        cf.is_required = false
      end
      
      [start_time, end_time]
    end
    
    def self.create_time_entry(attributes = {})
      user = attributes[:user] || create_user
      project = attributes[:project] || create_project
      issue = attributes[:issue] || create_issue(project)
      activity = attributes[:activity] || create_overtime_activity
      
      start_time_field, end_time_field = create_custom_fields
      
      time_entry = TimeEntry.new(
        project: project,
        issue: issue,
        user: user,
        activity: activity,
        hours: attributes[:hours] || 2.0,
        spent_on: attributes[:spent_on] || Date.today,
        comments: attributes[:comments] || 'Test time entry'
      )
      
      if attributes[:overtime] != false
        time_entry.custom_field_values = {
          start_time_field.id.to_s => attributes[:start_time] || RedmineWebhook::TestHelper::DEFAULT_START_TIME,
          end_time_field.id.to_s => attributes[:end_time] || RedmineWebhook::TestHelper::DEFAULT_END_TIME
        }
      end
      
      time_entry.save!
      time_entry
    end
  end
end
