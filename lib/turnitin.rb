# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

module Turnitin
  def self.state_from_similarity_score(similarity_score)
    return "none" if similarity_score == 0
    return "acceptable" if similarity_score < 25
    return "warning" if similarity_score < 50
    return "problem" if similarity_score < 75

    "failure"
  end

  class Client
    attr_accessor :endpoint, :account_id, :shared_secret, :host, :testing

    def initialize(account_id, shared_secret, host = nil, testing = false)
      @host = host || "api.turnitin.com"
      @endpoint = "/api.asp"
      raise "Account ID required" unless account_id
      raise "Shared secret required" unless shared_secret

      @account_id = account_id
      @shared_secret = shared_secret
      @testing = testing
      @functions = {
        create_user: "1", # instructor or student
        create_course: "2", # instructor only
        enroll_student: "3", # student only
        create_assignment: "4", # instructor only
        submit_paper: "5", # student or teacher
        generate_report: "6",
        show_paper: "7",
        delete_paper: "8",
        change_password: "9",
        list_papers: "10",
        check_user_paper: "11",
        view_admin_statistics: "12",
        view_grade_mark: "13",
        report_turnaround_times: "14",
        submission_scores: "15",
        login_user: "17",
        logout_user: "18",
      }
    end

    def id(obj)
      if @testing
        "test_#{obj.asset_string}"
      elsif obj.respond_to?(:turnitin_id)
        obj.turnitin_asset_string
      else
        "#{account_id}_#{obj.asset_string}"
      end
    end

    def email(item)
      # emails @example.com are, guaranteed by RFCs, to be like /dev/null :)
      email = if item.is_a?(User)
                item.email
              elsif item.respond_to?(:turnitin_id)
                "#{item.turnitin_asset_string}@null.instructure.example.com"
              end
      email || "#{item.asset_string}@null.instructure.example.com"
    end

    TurnitinUser = Struct.new(:asset_string, :first_name, :last_name, :name)

    def testSettings
      user = TurnitinUser.new("admin_test", "Admin", "Test", "Admin Test")
      res = createTeacher(user)
      res.success?
    end

    def createStudent(user)
      sendRequest(:create_user, 2, user:, utp: "1")
    end

    def createTeacher(user)
      sendRequest(:create_user, 2, user:, utp: "2")
    end

    def createCourse(course)
      sendRequest(:create_course, 2, course:, user: course, utp: "2")
    end

    def enrollStudent(course, student)
      sendRequest(:enroll_student, 2, user: student, course:, utp: "1", tem: email(course))
    end

    def self.default_assignment_turnitin_settings
      {
        originality_report_visibility: "immediate",
        s_paper_check: "1",
        internet_check: "1",
        journal_check: "1",
        exclude_biblio: "1",
        exclude_quoted: "1",
        exclude_type: "0",
        exclude_value: "",
        submit_papers_to: "1"
      }
    end

    def self.normalize_assignment_turnitin_settings(settings)
      unless settings.nil?
        valid_keys = Turnitin::Client.default_assignment_turnitin_settings.keys
        valid_keys << :created
        settings = settings.slice(*valid_keys)

        settings[:originality_report_visibility] = "immediate" unless %w[immediate after_grading after_due_date never].include?(settings[:originality_report_visibility])
        settings[:s_view_report] = determine_student_visibility(settings[:originality_report_visibility])

        %i[s_paper_check internet_check journal_check exclude_biblio exclude_quoted submit_papers_to].each do |key|
          bool = Canvas::Plugin.value_to_boolean(settings[key])
          settings[key] = bool ? "1" : "0"
        end
        exclude_value = settings[:exclude_value].to_i
        settings[:exclude_type] = "0" unless %w[0 1 2].include?(settings[:exclude_type])
        settings[:exclude_value] = case settings[:exclude_type]
                                   when "0" then ""
                                   when "1" then [exclude_value, 1].max.to_s
                                   when "2" then (0..100).cover?(exclude_value) ? exclude_value.to_s : "0"
                                   end
      end
      settings
    end

    def self.determine_student_visibility(originality_report_visibility)
      case originality_report_visibility
      when "immediate", "after_grading", "after_due_date"
        "1"
      when "never"
        "0"
      end
    end

    def createOrUpdateAssignment(assignment, settings)
      course = assignment.context
      # turnitin generally expects the timezone to be set the same as
      # the Turnitin account is set up as.
      today = course.time_zone.today
      settings = Turnitin::Client.normalize_assignment_turnitin_settings(settings)
      # institution_check   - 1/0, check institution
      # submit_papers_to    - 0=none, 1=standard, 2=institution
      response = sendRequest(:create_assignment, settings.delete(:created) ? "3" : "2", settings.merge!({
                                                                                                          user: course,
                                                                                                          course:,
                                                                                                          assignment:,
                                                                                                          utp: "2",
                                                                                                          dtstart: "#{today.strftime} 00:00:00",
                                                                                                          dtdue: "#{today.strftime} 00:00:00",
                                                                                                          dtpost: "#{today.strftime} 00:00:00",
                                                                                                          late_accept_flag: "1",
                                                                                                          post: true
                                                                                                        }))

      response.success? ? { assignment_id: response.assignment_id } : response.error_hash
    end

    # if asset_string is passed in, only submit that attachment
    def submitPaper(submission, asset_string = nil)
      student = submission.user
      assignment = submission.assignment
      course = assignment.context
      opts = {
        post: true,
        utp: "1",
        user: student,
        course:,
        assignment:,
        tem: email(course)
      }
      responses = {}
      if submission.submission_type == "online_upload"
        attachments = submission.attachments.select { |a| a.turnitinable? && (asset_string.nil? || a.asset_string == asset_string) }
        attachments.each do |a|
          responses[a.asset_string] = sendRequest(:submit_paper, "2", { ptl: a.display_name, pdata: a.open, ptype: "2" }.merge!(opts))
        end
      elsif submission.submission_type == "online_text_entry" && (asset_string.nil? || submission.asset_string == asset_string)
        responses[submission.asset_string] = sendRequest(:submit_paper, "2", { ptl: assignment.title, pdata: submission.plaintext_body, ptype: "1" }.merge!(opts))
      else
        raise "Unsupported submission type for turnitin integration: #{submission.submission_type}"
      end

      responses.transform_values! do |res|
        res.success? ? { object_id: res.returned_object_id } : res.error_hash
      end

      responses
    end

    def generateReport(submission, asset_string)
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data.dig(asset_string, :object_id)
      res = nil
      res = sendRequest(:generate_report, 2, oid: object_id, utp: "2", user: course, course:, assignment:) if object_id
      data = {}
      if res
        data[:similarity_score] = res.css("originalityscore").first.try(:content)
        data[:web_overlap] = res.css("web_overlap").first.try(:content)
        data[:publication_overlap] = res.css("publication_overlap").first.try(:content)
        data[:student_overlap] = res.css("student_paper_overlap").first.try(:content)
      end
      data
    end

    def submissionReportUrl(submission, asset_string)
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data.dig(asset_string, :object_id)
      sendRequest(:generate_report, 1, oid: object_id, utp: "2", user: course, course:, assignment:)
    end

    def submissionStudentReportUrl(submission, asset_string)
      user = submission.user
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data.dig(asset_string, :object_id)
      sendRequest(:generate_report, 1, oid: object_id, utp: "1", user:, course:, assignment:, tem: email(course))
    end

    def submissionPreviewUrl(submission, asset_string)
      user = submission.user
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data.dig(asset_string, :object_id)
      sendRequest(:show_paper, 1, oid: object_id, utp: "1", user:, course:, assignment:, tem: email(course))
    end

    def submissionDownloadUrl(submission, asset_string)
      user = submission.user
      assignment = submission.assignment
      course = assignment.context
      object_id = submission.turnitin_data.dig(asset_string, :object_id)
      sendRequest(:show_paper, 1, oid: object_id, utp: "1", user:, course:, assignment:, tem: email(course))
    end

    def listSubmissions(assignment)
      course = assignment.context
      sendRequest(:list_papers, 2, assignment:, course:, user: course, utp: "1", tem: email(course))
    end

    # From the turnitin api docs: To calculate the MD5, concatenate the data
    # values associated with the URL variables of ALL variables being sent, in
    # alphabetical order according to variable name, being sure to include at
    # least the following:
    #
    # aid + diagnostic + encrypt + fcmd + fid + gmtime + uem + ufn + uln + utp + shared secret key
    #
    # The shared secret key is added to the end of the parameters.
    #
    # From our testing, turnitin appears to be unescaping parameters and then
    # calculating MD5, so our MD5 should be calculated before parameters are
    # escaped
    def request_md5(params)
      keys_used = []
      str = ""
      keys = %i[aid assign assignid cid cpw ctl diagnostic dis dtdue dtstart dtpost encrypt fcmd fid gmtime newassign newupw oid pfn pln ptl ptype said tem uem ufn uid uln upw utp]
      keys.each do |key|
        keys_used << key if params[key].present?
        str += params[key] || ""
      end
      str += @shared_secret
      Digest::MD5.hexdigest(str)
    end

    def escape_params(params)
      escaped_params = {}
      params.each do |key, value|
        escaped_params[key] = if value.is_a?(String)
                                CGI.escape(value).gsub("+", "%20")
                              # turnitin uses %20 to encode spaces (instead of +)
                              else
                                value
                              end
      end
      escaped_params
    end

    def prepare_params(command, fcmd, args)
      user = args.delete :user
      course = args.delete :course
      assignment = args.delete :assignment
      post = args.delete :post
      params = args.merge({
                            gmtime: Time.now.utc.strftime("%Y%m%d%H%M")[0, 11],
                            fid: @functions[command],
                            fcmd: fcmd.to_s,
                            encrypt: "0",
                            aid: @account_id,
                            src: "15",
                            dis: "1"
                          })
      if user
        params[:uid] = id(user)
        params[:uem] = email(user)
        if user.is_a?(Course)
          params[:ufn] = user.name
          params[:uln] = "Course"
        else
          params[:ufn] = user.first_name
          params[:uln] = user.last_name
          params[:uln] = "Student" if params[:uln].empty?
        end
      end
      if course
        params[:cid] = id(course)
        params[:ctl] = course.name
      end
      if assignment
        params[:assign] = "#{assignment.title} - #{assignment.id}"
        params[:assignid] = id(assignment)
      end
      params[:diagnostic] = "1" if @testing

      params[:md5] = request_md5(params)
      params = escape_params(params) if post
      params
    end

    def sendRequest(command, fcmd, args)
      require "net/http"

      post = args[:post] # gets deleted in prepare_params
      params = prepare_params(command, fcmd, args)

      if post
        query, headers = LegacyMultipart::Post.prepare_query(params)
        http = Net::HTTP.new(@host, 443)
        http.use_ssl = true
        http_response = http.start do |con|
          req = Net::HTTP::Post.new(@endpoint, headers)
          con.read_timeout = 30
          begin
            con.request(req, query)
          rescue => e
            Rails.logger.error("Turnitin API error for account_id #{@account_id}: POSTING FAILED")
            Rails.logger.error(params.to_json)
            Canvas::Errors.capture(e, { tags: { type: "turnitin_api_unreachable", host: @host, endpoint: @endpoint } })
            raise e
          end
        end
      else
        requestParams = ""
        params.each do |key, value|
          next if value.nil?

          requestParams += "&#{URI::DEFAULT_PARSER.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
        end
        if params[:fcmd] == "1"
          return "https://#{@host}#{@endpoint}?#{requestParams}"
        else
          http = Net::HTTP.new(@host, 443)
          http.use_ssl = true
          http_response = http.start do |conn|
            conn.get("#{@endpoint}?#{requestParams}")
          end
        end
      end

      return nil if @testing

      response = Turnitin::Response.new(http_response)
      if response.error?
        Rails.logger.error("Turnitin API error for account_id #{@account_id}: error #{response.return_code}")
        Rails.logger.error(params.to_json)
        Rails.logger.error(http_response.body)
      end
      response
    end
  end
end
