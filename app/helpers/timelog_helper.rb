# Redmine - project management software
# Copyright (C) 2006-2011  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

module TimelogHelper
  include ApplicationHelper

  def render_timelog_breadcrumb
    links = []
    links << link_to(l(:label_project_all), {:project_id => nil, :issue_id => nil})
    links << link_to(h(@project), {:project_id => @project, :issue_id => nil}) if @project
    if @issue
      if @issue.visible?
        links << link_to_issue(@issue, :subject => false)
      else
        links << "##{@issue.id}"
      end
    end
    breadcrumb links
  end

  # Returns a collection of activities for a select field.  time_entry
  # is optional and will be used to check if the selected TimeEntryActivity
  # is active.
  def activity_collection_for_select_options(time_entry=nil, project=nil)
    project ||= @project
    if project.nil?
      activities = TimeEntryActivity.shared.active
    else
      activities = project.activities
    end

    collection = []
    if time_entry && time_entry.activity && !time_entry.activity.active?
      collection << [ "--- #{l(:actionview_instancetag_blank_option)} ---", '' ]
    else
      collection << [ "--- #{l(:actionview_instancetag_blank_option)} ---", '' ] unless activities.detect(&:is_default)
    end
    activities.each { |a| collection << [a.name, a.id] }
    collection
  end

  def select_hours(data, criteria, value)
  	if value.to_s.empty?
  		data.select {|row| row[criteria].blank? }
    else
    	data.select {|row| row[criteria].to_s == value.to_s}
    end
  end

  def sum_hours(data)
    sum = 0
    data.each do |row|
      sum += row['hours'].to_f
    end
    sum
  end

  def options_for_period_select(value)
    options_for_select([[l(:label_all_time), 'all'],
                        [l(:label_today), 'today'],
                        [l(:label_yesterday), 'yesterday'],
                        [l(:label_this_week), 'current_week'],
                        [l(:label_last_week), 'last_week'],
                        [l(:label_last_n_days, 7), '7_days'],
                        [l(:label_this_month), 'current_month'],
                        [l(:label_last_month), 'last_month'],
                        [l(:label_last_n_days, 30), '30_days'],
                        [l(:label_this_year), 'current_year']],
                        value)
  end

  def entries_to_csv(entries)
    decimal_separator = l(:general_csv_decimal_separator)
    custom_fields = TimeEntryCustomField.find(:all)
    export = FCSV.generate(:col_sep => l(:general_csv_separator)) do |csv|
      # csv header fields
      headers = [l(:field_spent_on),
                 l(:field_user),
                 l(:field_activity),
                 l(:field_project),
                 l(:field_issue),
                 l(:field_tracker),
                 l(:field_subject),
                 l(:field_hours),
                 l(:field_comments)
                 ]
      # Export custom fields
      headers += custom_fields.collect(&:name)

      csv << headers.collect {|c| Redmine::CodesetUtil.from_utf8(
                                     c.to_s,
                                     l(:general_csv_encoding) )  }
      # csv lines
      entries.each do |entry|
        fields = [format_date(entry.spent_on),
                  entry.user,
                  entry.activity,
                  entry.project,
                  (entry.issue ? entry.issue.id : nil),
                  (entry.issue ? entry.issue.tracker : nil),
                  (entry.issue ? entry.issue.subject : nil),
                  entry.hours.to_s.gsub('.', decimal_separator),
                  entry.comments
                  ]
        fields += custom_fields.collect {|f| show_value(entry.custom_value_for(f)) }

        csv << fields.collect {|c| Redmine::CodesetUtil.from_utf8(
                                     c.to_s,
                                     l(:general_csv_encoding) )  }
      end
    end
    export
  end

  def format_criteria_value(criteria, value)
    if value.blank?
      l(:label_none)
    elsif k = @available_criterias[criteria][:klass]
      obj = k.find_by_id(value.to_i)
      if obj.is_a?(Issue)
        obj.visible? ? "#{obj.tracker} ##{obj.id}: #{obj.subject}" : "##{obj.id}"
      else
        obj
      end
    else
      format_value(value, @available_criterias[criteria][:format])
    end
  end

  def report_to_csv(criterias, periods, hours)
    decimal_separator = l(:general_csv_decimal_separator)
    export = FCSV.generate(:col_sep => l(:general_csv_separator)) do |csv|
      # Column headers
      headers = criterias.collect {|criteria| l(@available_criterias[criteria][:label]) }
      headers += periods
      headers << l(:label_total)
      csv << headers.collect {|c| Redmine::CodesetUtil.from_utf8(
                                    c.to_s,
                                    l(:general_csv_encoding) ) }
      # Content
      report_criteria_to_csv(csv, criterias, periods, hours)
      # Total row
      str_total = Redmine::CodesetUtil.from_utf8(l(:label_total), l(:general_csv_encoding))
      row = [ str_total ] + [''] * (criterias.size - 1)
      total = 0
      periods.each do |period|
        sum = sum_hours(select_hours(hours, @columns, period.to_s))
        total += sum
        row << (sum > 0 ? ("%.2f" % sum).gsub('.',decimal_separator) : '')
      end
      row << ("%.2f" % total).gsub('.',decimal_separator)
      csv << row
    end
    export
  end

  def report_criteria_to_csv(csv, criterias, periods, hours, level=0)
    decimal_separator = l(:general_csv_decimal_separator)
    hours.collect {|h| h[criterias[level]].to_s}.uniq.each do |value|
      hours_for_value = select_hours(hours, criterias[level], value)
      next if hours_for_value.empty?
      row = [''] * level
      row << Redmine::CodesetUtil.from_utf8(
                        format_criteria_value(criterias[level], value).to_s,
                        l(:general_csv_encoding) )
      row += [''] * (criterias.length - level - 1)
      total = 0
      periods.each do |period|
        sum = sum_hours(select_hours(hours_for_value, @columns, period.to_s))
        total += sum
        row << (sum > 0 ? ("%.2f" % sum).gsub('.',decimal_separator) : '')
      end
      row << ("%.2f" % total).gsub('.',decimal_separator)
      csv << row
      if criterias.length > level + 1
        report_criteria_to_csv(csv, criterias, periods, hours_for_value, level + 1)
      end
    end
  end
end
