# frozen_string_literal: true

#
# Copyright (C) 2013 Instructure, Inc.
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

require_relative "../api_spec_helper"

describe "Outcome Results API", type: :request do
  let_once(:outcome_course) do
    course_factory(active_all: true)
    @course
  end

  let_once(:outcome_teacher) do
    teacher_in_course(active_all: true, course: outcome_course)
    @teacher
  end

  let_once(:outcome_student) do
    student_in_course(active_all: true, course: outcome_course)
    @student
  end

  let_once(:outcome_rubric) do
    create_outcome_rubric
  end

  let_once(:outcome_object) do
    outcome_rubric
    @outcome
  end

  let_once(:outcome_assignment) do
    assignment = create_outcome_assignment
    find_or_create_outcome_submission(assignment:)
    assignment
  end

  let_once(:live_assessment) do
    LiveAssessments::Assessment.create!(
      key: "live_assess",
      title: "MagicMarker",
      context: @course
    )
  end

  let_once(:outcome_rubric_association) do
    create_outcome_rubric_association
  end

  let(:outcome_criterion) do
    find_outcome_criterion
  end

  let(:first_outcome_rating) do # 3 points
    find_first_rating
  end

  let(:outcome_assessment) do
    create_outcome_assessment
  end

  def find_or_create_outcome_submission(opts = {})
    student = opts[:student] || outcome_student
    assignment = opts[:assignment] ||
                 (create_outcome_assignment if opts[:new]) ||
                 outcome_assignment
    assignment.find_or_create_submission(student)
  end

  def create_outcome_live_assessment
    @outcome.align(live_assessment, @course)
    LiveAssessments::Result.create!(
      user: outcome_student,
      assessor_id: outcome_teacher.id,
      assessment_id: live_assessment.id,
      passed: true,
      assessed_at: Time.zone.now
    )
    live_assessment.generate_submissions_for([outcome_student])
  end

  def create_outcome_assessment(opts = {})
    association = (create_outcome_rubric_association(opts) if opts[:new]) ||
                  outcome_rubric_association
    criterion = find_outcome_criterion(association.rubric)
    submission = opts[:submission] || find_or_create_outcome_submission(opts)
    student = submission.student
    points = opts[:points] ||
             find_first_rating(criterion)[:points]
    association.assess(
      user: student,
      assessor: outcome_teacher,
      artifact: submission,
      assessment: {
        assessment_type: "grading",
        "criterion_#{criterion[:id]}": {
          points:
        }
      }
    )
  end

  def create_outcome_rubric
    outcome_course
    outcome_with_rubric(mastery_points: 3)
    @outcome.rubric_criterion = find_outcome_criterion(@rubric)
    @outcome.save
    @rubric
  end

  def create_outcome_assignment
    outcome_course.assignments.create!(
      title: "outcome assignment",
      description: "this is an outcome assignment",
      points_possible: outcome_rubric.points_possible
    )
  end

  def create_outcome_rubric_association(opts = {})
    rubric = (create_outcome_rubric if opts[:new]) ||
             outcome_rubric
    assignment = (create_outcome_assignment if opts[:new]) ||
                 outcome_assignment
    rubric.associate_with(assignment, outcome_course, purpose: "grading", use_for_grading: true)
  end

  def find_outcome_criterion(rubric = outcome_rubric)
    rubric.criteria.find { |c| !c[:learning_outcome_id].nil? }
  end

  def find_first_rating(criterion = outcome_criterion)
    criterion[:ratings].first
  end

  let(:outcome_result) do
    outcome_assessment
    outcome_object.reload.learning_outcome_results.first
  end

  let(:outcome_students) do
    (0..3).map do |i|
      student = student_in_course(active_all: true).user
      create_outcome_assessment(student:, points: i)
      student
    end
  end

  let(:outcome_course_sections) do
    [0, 1].map { |i| outcome_course.course_sections.create(name: "section #{i}") }
  end

  let(:sectioned_outcome_students) do
    0.upto(3).map do |i|
      student = student_in_section(outcome_course_sections[i % 2])
      create_outcome_assessment(student:, points: i)
      student
    end
  end

  def outcome_rollups_url(context, params = {})
    api_v1_course_outcome_rollups_url(context, params)
  end

  def outcome_results_url(context, params = {})
    api_v1_course_outcome_results_url(context, params)
  end

  def student_enrollment_status(course, student, section = nil)
    student_enrollments = course.all_accepted_student_enrollments.where(user_id: student.id)
    return student_enrollments.where(course_section_id: section.id).first.workflow_state unless section.nil?

    student_enrollments.first.workflow_state
  end

  before do
    @user = @teacher # api calls as teacher, by default
  end

  describe "outcome rollups" do
    describe "error handling" do
      it "requires manage grades permisssion" do
        @user = @student
        raw_api_call(:get,
                     outcome_rollups_url(outcome_course),
                     controller: "outcome_results",
                     action: "rollups",
                     format: "json",
                     course_id: outcome_course.id.to_s)
        assert_forbidden
      end

      it "allows students to read their own results" do
        @user = outcome_students[0]
        raw_api_call(:get,
                     outcome_rollups_url(outcome_course),
                     controller: "outcome_results",
                     action: "rollups",
                     format: "json",
                     course_id: outcome_course.id.to_s,
                     user_ids: [outcome_students[0].id])
        assert_status(200)
      end

      it "does not allow students to read other users' results" do
        @user = outcome_students[0]
        raw_api_call(:get,
                     outcome_rollups_url(outcome_course),
                     controller: "outcome_results",
                     action: "rollups",
                     format: "json",
                     course_id: outcome_course.id.to_s,
                     user_ids: [outcome_students[1].id])
        assert_forbidden
      end

      it "does not allow students to read other users' results via csv" do
        user_session outcome_students[0]
        get "/courses/#{@course.id}/outcome_rollups.csv"
        assert_forbidden
      end

      it "requires an existing context" do
        bogus_course = Course.new { |c| c.id = -1 }
        raw_api_call(:get,
                     outcome_rollups_url(bogus_course),
                     controller: "outcome_results",
                     action: "rollups",
                     format: "json",
                     course_id: bogus_course.id.to_s)
        assert_status(404)
      end

      it "verifies the aggregate parameter" do
        raw_api_call(:get,
                     outcome_rollups_url(@course, aggregate: "invalid"),
                     controller: "outcome_results",
                     action: "rollups",
                     format: "json",
                     course_id: @course.id.to_s,
                     aggregate: "invalid")
        assert_status(400)
      end

      it "requires user ids to be students in the context" do
        raw_api_call(:get,
                     outcome_rollups_url(@course, user_ids: @teacher.id.to_s),
                     controller: "outcome_results",
                     action: "rollups",
                     format: "json",
                     course_id: @course.id.to_s,
                     user_ids: @teacher.id)
        assert_status(400)
      end

      it "requires section id to be a section in the context" do
        bogus_section = course_factory(active_course: true).course_sections.create!(name: "bogus section")
        raw_api_call(:get,
                     outcome_rollups_url(outcome_course, section_id: bogus_section.id),
                     controller: "outcome_results",
                     action: "rollups",
                     format: "json",
                     course_id: outcome_course.id.to_s,
                     section_id: bogus_section.id.to_s)
        assert_status(400)
      end

      it "verifies the include[] parameter" do
        raw_api_call(:get,
                     outcome_rollups_url(@course, include: ["invalid"]),
                     controller: "outcome_results",
                     action: "rollups",
                     format: "json",
                     course_id: @course.id.to_s,
                     include: ["invalid"])
        assert_status(400)
      end
    end

    describe "basic response" do
      it "returns a json api structure" do
        outcome_result
        api_call(:get,
                 outcome_rollups_url(outcome_course),
                 controller: "outcome_results",
                 action: "rollups",
                 format: "json",
                 course_id: outcome_course.id.to_s)
        json = JSON.parse(response.body)
        expect(json.keys.sort).to eq %w[meta rollups]
        expect(json["rollups"].size).to eq 1
        json["rollups"].each do |rollup|
          expect(rollup.keys.sort).to eq %w[links scores]
          expect(rollup["links"].keys.sort).to eq %w[section status user]
          expect(rollup["links"]["section"]).to eq @course.course_sections.first.id.to_s
          expect(rollup["links"]["status"]).to eq student_enrollment_status(@course, outcome_student, @course.course_sections.first)
          expect(rollup["links"]["user"]).to eq outcome_student.id.to_s
          expect(rollup["scores"].size).to eq 1
          rollup["scores"].each do |score|
            expect(score.keys.sort).to eq %w[count hide_points links score submitted_at title]
            expect(score["count"]).to eq 1
            expect(score["score"]).to eq first_outcome_rating[:points]
            expect(score["links"].keys.sort).to eq %w[outcome]
            expect(score["links"]["outcome"]).to eq outcome_object.id.to_s
          end
        end
      end

      context "csv" do
        it "returns a csv file" do
          outcome_result
          user_session @user
          get "/courses/#{@course.id}/outcome_rollups.csv"
          expect(response).to be_successful
          expect(response.body).to eq <<~CSV
            Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
            User,#{outcome_student.id},N/A,3.0,3.0
          CSV
        end

        it "obeys csv i18n flags" do
          @user.enable_feature! :include_byte_order_mark_in_gradebook_exports
          @user.enable_feature! :use_semi_colon_field_separators_in_gradebook_exports

          outcome_result
          user_session @user
          get "/courses/#{@course.id}/outcome_rollups.csv"
          expect(response).to be_successful
          expect(response.body).to eq <<~CSV
            \xEF\xBB\xBFStudent name;Student ID;Student SIS ID;new outcome result;new outcome mastery points
            User;#{outcome_student.id};N/A;3.0;3.0
          CSV
        end

        context "exports with student sis_ids" do
          it "returns sis_ids for students that have them" do
            pseudonym_student = User.create!(name: "Student - Pseudonym")
            pseudonym_student = user_with_pseudonym(user: pseudonym_student, sis_user_id: "student_1")
            pseudonym_student.register!
            @course.enroll_student(pseudonym_student)
            create_outcome_assessment(student: pseudonym_student)
            outcome_result

            user_session @user
            get "/courses/#{@course.id}/outcome_rollups.csv"
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              Student - Pseudonym,#{pseudonym_student.id},student_1,3.0,3.0
              User,#{outcome_student.id},N/A,3.0,3.0
            CSV
          end

          it "returns correct sis_id for students with multiple pseudonyms" do
            pseudonym_student = User.create!(name: "Student - Pseudonym")
            p1 = Pseudonym.create!(unique_id: "deleted_pseudonym@instructure.com", user: pseudonym_student, sis_user_id: "bad_student")
            Pseudonym.create!(unique_id: "active_pseudonym@instructure.com", user: pseudonym_student, sis_user_id: "student_1")
            # Delete the first pseudonym
            p1.workflow_state = "deleted"
            p1.save!
            # Register student
            pseudonym_student.register!
            @course.enroll_student(pseudonym_student)
            create_outcome_assessment(student: pseudonym_student)
            outcome_result

            user_session @user
            get "/courses/#{@course.id}/outcome_rollups.csv"
            expect(response).to be_successful
            expect(pseudonym_student.pseudonyms.length).to eq 2
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              Student - Pseudonym,#{pseudonym_student.id},student_1,3.0,3.0
              User,#{outcome_student.id},N/A,3.0,3.0
            CSV
          end
        end

        context "when Account-level Mastery Scales flag is on" do
          before do
            @course.account.enable_feature!(:account_level_mastery_scales)
          end

          it "uses default outcome_proficiency values for points scaling if no outcome proficiency exists" do
            outcome_result
            user_session @user

            get "/courses/#{@course.id}/outcome_rollups.csv"
            outcome_proficiency = OutcomeProficiency.find_or_create_default!(@course)
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              User,#{outcome_student.id},N/A,#{outcome_proficiency.points_possible},#{outcome_proficiency.mastery_points}
            CSV
          end

          it "uses resolved_outcome_proficiency for points scaling if one exists" do
            outcome_proficiency_model(@course)
            outcome_result
            user_session @user

            get "/courses/#{@course.id}/outcome_rollups.csv"
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              User,#{outcome_student.id},N/A,10.0,10.0
            CSV
          end
        end

        context "Student filters in LMGB FF" do
          before do
            @concluded_student = User.create!(name: "Student - Concluded")
            @concluded_student.register!
            @course.enroll_student(@concluded_student)
            create_outcome_assessment(student: @concluded_student)
            @concluded_student.enrollments.first.conclude

            @inactive_student = User.create!(name: "Student - Inactive")
            @inactive_student.register!
            @course.enroll_student(@inactive_student)
            create_outcome_assessment(student: @inactive_student)
            @inactive_student.enrollments.first.deactivate

            @no_results_student = User.create!(name: "Student - No Results")
            @no_results_student.register!
            @course.enroll_student(@no_results_student)

            @observer = User.create!(name: "Observer")
            @observer.register!
            @course.enroll_user(@observer, "ObserverEnrollment", associated_user_id: @no_results_student.id, enrollment_state: "active")

            outcome_result # Creates result for enrolled student outcome_student
          end

          it "doesn't display concluded students when exclude[]=concluded_enrollments is present" do
            user_session @user
            get "/courses/#{@course.id}/outcome_rollups.csv?exclude[]=concluded_enrollments"
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              #{@inactive_student.name},#{@inactive_student.id},N/A,3.0,3.0
              #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
              #{@no_results_student.name},#{@no_results_student.id},N/A,,3.0
            CSV
          end

          it "doesn't display concluded students when exclude[]=concluded_enrollments and section_id is given" do
            section1 = add_section "s1", course: outcome_course
            student_in_section section1, user: outcome_student, allow_multiple_enrollments: true
            student_in_section section1, user: @concluded_student, allow_multiple_enrollments: true
            @concluded_student.enrollments.map(&:conclude)

            user_session @user
            get "/courses/#{@course.id}/outcome_rollups.csv?exclude[]=concluded_enrollments&section_id=#{section1.id}"
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
            CSV
          end

          it "doesn't display inactive students when exclude[]=inactive_enrollments is present" do
            user_session @user
            get "/courses/#{@course.id}/outcome_rollups.csv?exclude[]=inactive_enrollments"
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              #{@concluded_student.name},#{@concluded_student.id},N/A,3.0,3.0
              #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
              #{@no_results_student.name},#{@no_results_student.id},N/A,,3.0
            CSV
          end

          it "doesn't display concluded students when exclude[]=inactive_enrollments and section_id is given" do
            section1 = add_section "s1", course: outcome_course
            student_in_section section1, user: outcome_student, allow_multiple_enrollments: true
            student_in_section section1, user: @inactive_student, allow_multiple_enrollments: true
            @inactive_student.enrollments.map(&:deactivate)

            user_session @user
            get "/courses/#{@course.id}/outcome_rollups.csv?exclude[]=inactive_enrollments&section_id=#{section1.id}"
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
            CSV
          end

          it "doesn't display no results students when exclude[]=missing_user_rollups is present" do
            user_session @user
            get "/courses/#{@course.id}/outcome_rollups.csv?exclude[]=missing_user_rollups"
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              #{@concluded_student.name},#{@concluded_student.id},N/A,3.0,3.0
              #{@inactive_student.name},#{@inactive_student.id},N/A,3.0,3.0
              #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
            CSV
          end

          it "displays concluded, inactive, and no results students when they are not excluded" do
            user_session @user
            get "/courses/#{@course.id}/outcome_rollups.csv"
            expect(response).to be_successful
            expect(response.body).to eq <<~CSV
              Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
              #{@concluded_student.name},#{@concluded_student.id},N/A,3.0,3.0
              #{@inactive_student.name},#{@inactive_student.id},N/A,3.0,3.0
              #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
              #{@no_results_student.name},#{@no_results_student.id},N/A,,3.0
            CSV
          end

          context "users with multiple enrollments" do
            before do
              @section1 = add_section "s1", course: outcome_course
              student_in_section @section1, user: outcome_student, allow_multiple_enrollments: true
              student_in_section @section1, user: @inactive_student, allow_multiple_enrollments: true
              student_in_section @section1, user: @concluded_student, allow_multiple_enrollments: true
            end

            it "displays concluded, inactive, and no results students when they arent excluded in a section" do
              student_in_section @section1, user: @no_results_student, allow_multiple_enrollments: true
              @no_results_student.enrollments.first.accept
              @inactive_student.enrollments.map(&:deactivate)
              @concluded_student.enrollments.map(&:conclude)
              user_session @user
              get "/courses/#{@course.id}/outcome_rollups.csv?section_id=#{@section1.id}"
              expect(response).to be_successful
              expect(response.body).to eq <<~CSV
                Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
                #{@concluded_student.name},#{@concluded_student.id},N/A,3.0,3.0
                #{@inactive_student.name},#{@inactive_student.id},N/A,3.0,3.0
                #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
                #{@no_results_student.name},#{@no_results_student.id},N/A,,3.0
              CSV
            end

            it "students with an active enrollment are always present" do
              user_session @user
              get "/courses/#{@course.id}/outcome_rollups.csv?exclude[]=inactive_enrollments&exclude[]=concluded_enrollments"
              expect(response).to be_successful
              expect(response.body).to eq <<~CSV
                Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
                #{@concluded_student.name},#{@concluded_student.id},N/A,3.0,3.0
                #{@inactive_student.name},#{@inactive_student.id},N/A,3.0,3.0
                #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
                #{@no_results_student.name},#{@no_results_student.id},N/A,,3.0
              CSV
            end

            it "users with inactive and concluded enrollments do display when only one is excluded" do
              @inactive_student.enrollments.last.conclude
              @concluded_student.enrollments.last.deactivate
              user_session @user
              get "/courses/#{@course.id}/outcome_rollups.csv?exclude[]=inactive_enrollments"
              expect(response).to be_successful
              expect(response.body).to eq <<~CSV
                Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
                #{@concluded_student.name},#{@concluded_student.id},N/A,3.0,3.0
                #{@inactive_student.name},#{@inactive_student.id},N/A,3.0,3.0
                #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
                #{@no_results_student.name},#{@no_results_student.id},N/A,,3.0
              CSV
            end

            it "users with inactive and concluded enrollments dont display when both are excluded" do
              @inactive_student.enrollments.last.conclude
              @concluded_student.enrollments.last.deactivate
              user_session @user
              get "/courses/#{@course.id}/outcome_rollups.csv?exclude[]=inactive_enrollments&exclude[]=concluded_enrollments"
              expect(response).to be_successful
              expect(response.body).to eq <<~CSV
                Student name,Student ID,Student SIS ID,new outcome result,new outcome mastery points
                #{outcome_student.name},#{outcome_student.id},N/A,3.0,3.0
                #{@no_results_student.name},#{@no_results_student.id},N/A,,3.0
              CSV
            end
          end
        end
      end

      describe "user_ids parameter" do
        it "restricts results to specified users" do
          # api endpoint requires an array of strings
          student_ids = outcome_students[0..1].map { |u| u.id.to_s }
          @user = @teacher

          api_call(:get,
                   outcome_rollups_url(outcome_course, user_ids: student_ids, include: ["users"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   user_ids: student_ids,
                   include: ["users"])
          json = JSON.parse(response.body)
          expect(json.keys.sort).to eq %w[linked meta rollups]
          expect(json["rollups"].size).to eq 2
          json["rollups"].each do |rollup|
            expect(rollup.keys.sort).to eq %w[links scores]
            expect(rollup["links"].keys.sort).to eq %w[section status user]
            expect(rollup["links"]["section"]).to eq @course.course_sections.first.id.to_s
            expect(rollup["links"]["status"]).to eq student_enrollment_status(@course, outcome_student, @course.course_sections.first)
            expect(student_ids).to include(rollup["links"]["user"])
            expect(rollup["scores"].size).to eq 1
            rollup["scores"].each do |score|
              expect(score.keys.sort).to eq %w[count hide_points links score submitted_at title]
              expect(score["count"]).to eq 1
              expect(score["score"]).to be_in [0, 1]
              expect(score["links"].keys.sort).to eq %w[outcome]
              expect(score["links"]["outcome"]).to eq outcome_object.id.to_s
            end
          end
          expect(json["linked"].keys.sort).to eq %w[users]
          expect(json["linked"]["users"].size).to eq 2
        end

        it "can require_outcome_context with sis_user_ids" do
          @user = @student
          pseudonym = pseudonym_model
          pseudonym.user_id = @student.id
          pseudonym.sis_user_id = "123"
          pseudonym.save
          # rollups api requires user_ids to be an array
          api_call(:get,
                   outcome_results_url(outcome_course, user_ids: ["sis_user_id:123"], include: ["users"]),
                   controller: "outcome_results",
                   action: "index",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   user_ids: ["sis_user_id:123"],
                   include: ["users"])
          json = JSON.parse(response.body)
          expect(json["linked"]["users"][0]["id"].to_i).to eq @student.id
        end

        it "can take sis_user_ids" do
          student_ids = outcome_students[0..1].map { |u| u.id.to_s }
          sis_id_student = outcome_students[2]
          pseudonym = pseudonym_model
          pseudonym.user_id = sis_id_student.id
          pseudonym.sis_user_id = "123"
          pseudonym.save
          student_ids << "sis_user_id:123"
          @user = @teacher
          #  rollups api requires that student_ids is an array
          api_call(:get,
                   outcome_rollups_url(outcome_course, user_ids: student_ids, include: ["users"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   user_ids: student_ids,
                   include: ["users"])
          json = JSON.parse(response.body)
          expect(json["linked"]["users"].size).to eq 3
          expect(json["linked"]["users"].map { |h| h["id"].to_i }.max).to eq sis_id_student.id
        end
      end

      describe "section_id parameter" do
        it "restricts results to the specified section" do
          sectioned_outcome_students
          @user = @teacher
          api_call(:get,
                   outcome_rollups_url(outcome_course, section_id: outcome_course_sections[0].id, include: ["users"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   section_id: outcome_course_sections[0].id.to_s,
                   include: ["users"])
          json = JSON.parse(response.body)
          expect(json.keys.sort).to eq %w[linked meta rollups]
          expect(json["rollups"].size).to eq 2
          json["rollups"].each do |rollup|
            expect(rollup.keys.sort).to eq %w[links scores]
            expect(rollup["links"].keys.sort).to eq %w[section status user]
            expect(rollup["links"]["section"]).to eq outcome_course_sections[0].id.to_s
            expect(rollup["links"]["status"]).to eq student_enrollment_status(outcome_course, outcome_course_sections.first.students.first, outcome_course_sections.first)
            expect(outcome_course_sections[0].student_ids.map(&:to_s)).to include(rollup["links"]["user"])
            expect(rollup["scores"].size).to eq 1
            rollup["scores"].each do |score|
              expect(score.keys.sort).to eq %w[count hide_points links score submitted_at title]
              expect(score["count"]).to eq 1
              expect(score["score"]).to be_in [0, 2]
              expect(score["links"].keys.sort).to eq %w[outcome]
              expect(score["links"]["outcome"]).to eq outcome_object.id.to_s
            end
          end
          expect(json["linked"].keys.sort).to eq %w[users]
          expect(json["linked"]["users"].size).to eq outcome_course_sections[0].students.count
        end

        it "users with rejected enrollments are included" do
          rejected_student = User.create!(name: "Student - Rejected")
          rejected_student.register!
          section1 = add_section "s1", course: outcome_course
          student_in_section section1, user: rejected_student, allow_multiple_enrollments: true
          rejected_student.enrollments.first.reject
          user_session @teacher
          api_call(:get,
                   outcome_rollups_url(outcome_course, section_id: section1.id.to_s, include: ["users"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   section_id: section1.id.to_s,
                   include: ["users"])
          json = JSON.parse(response.body)
          expect(json["linked"]["users"].size).to eq 1
          expect(json["linked"]["users"][0]["name"]).to eq "Student - Rejected"
        end
      end

      describe "include[] parameter" do
        it "side loads courses" do
          api_call(:get,
                   outcome_rollups_url(outcome_course, include: ["courses"], aggregate: "course"),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   include: ["courses"],
                   aggregate: "course")
          json = JSON.parse(response.body)
          expect(json["linked"]).to be_present
          expect(json["linked"]["courses"]).to be_present
          expect(json["linked"]["courses"][0]["id"]).to eq outcome_course.id.to_s
        end

        it "side loads outcomes" do
          api_call(:get,
                   outcome_rollups_url(outcome_course, include: ["outcomes"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   include: ["outcomes"])
          json = JSON.parse(response.body)
          expect(json["linked"]).to be_present
          expect(json["linked"]["outcomes"]).to be_present
          expect(json["linked"]["outcomes"][0]["id"]).to eq outcome_object.id
        end

        it "side loads outcome groups" do
          root_group = outcome_course.root_outcome_group
          child_group = root_group.child_outcome_groups.create!(title: "child group")
          grandchild_group = child_group.child_outcome_groups.create!(title: "grandchild_group")
          api_call(:get,
                   outcome_rollups_url(outcome_course, include: ["outcome_groups"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   include: ["outcome_groups"])
          json = JSON.parse(response.body)
          expect(json["linked"]).to be_present
          expect(json["linked"]["outcome_groups"]).to be_present
          group_titles = json["linked"]["outcome_groups"].pluck("id").sort
          expected_titles = [root_group, child_group, grandchild_group].map(&:id).sort
          expect(group_titles).to eq expected_titles
        end

        it "side loads outcome links" do
          api_call(:get,
                   outcome_rollups_url(outcome_course, include: ["outcome_links"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   include: ["outcome_links"])
          json = JSON.parse(response.body)
          expect(json["linked"]).to be_present
          expect(json["linked"]["outcome_links"]).to be_present
          expect(json["linked"]["outcome_links"].first["outcome_group"]["id"]).to eq(
            outcome_course.root_outcome_group.id
          )
          expect(json["linked"]["outcome_links"].first["outcome"]["id"]).to eq(
            outcome_object.id
          )
        end

        it "side loads users" do
          outcome_assessment
          api_call(:get,
                   outcome_rollups_url(outcome_course, include: ["users"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   include: ["users"])
          json = JSON.parse(response.body)
          expect(json["linked"]).to be_present
          expect(json["linked"]["users"]).to be_present
          expect(json["linked"]["users"][0]["id"]).to eq outcome_student.id.to_s
        end

        it "side loads alignments" do
          outcome_assessment
          api_call(:get,
                   outcome_rollups_url(outcome_course, include: ["outcomes", "outcomes.alignments"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   include: ["outcomes", "outcomes.alignments"])
          json = JSON.parse(response.body)
          expect(json["linked"]).to be_present
          expect(json["linked"]["outcomes"]).to be_present
          expect(json["linked"]["outcomes.alignments"]).to be_present
          expect(json["linked"]["outcomes"][0]["alignments"].sort).to eq [outcome_assignment.asset_string, outcome_rubric.asset_string]
          alignments = json["linked"]["outcomes.alignments"]
          alignments.sort_by! { |a| a["id"] }
          expect(alignments[0]["id"]).to eq outcome_assignment.asset_string
          expect(alignments[0]["name"]).to eq outcome_assignment.name
          expect(alignments[0]["html_url"]).to eq course_assignment_url(outcome_course, outcome_assignment)
          expect(alignments[1]["id"]).to eq outcome_rubric.asset_string
          expect(alignments[1]["name"]).to eq outcome_rubric.title
          expect(alignments[1]["html_url"]).to eq course_rubric_url(outcome_course, outcome_rubric)
        end

        it "side loads alignments with live assessment" do
          create_outcome_live_assessment
          api_call(:get,
                   outcome_rollups_url(outcome_course, include: ["outcomes.alignments"]),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   include: ["outcomes.alignments"])
          json = JSON.parse(response.body)
          expect(json["linked"]).to be_present
          expect(json["linked"]["outcomes.alignments"]).to be_present
          alignments = json["linked"]["outcomes.alignments"]
          alignments.sort_by! { |a| a["id"] }
          expect(alignments[0]["id"]).to eq outcome_assignment.asset_string
          expect(alignments[0]["name"]).to eq outcome_assignment.name
          expect(alignments[0]["html_url"]).to eq course_assignment_url(outcome_course, outcome_assignment)
          expect(alignments[1]["id"]).to eq live_assessment.asset_string
          expect(alignments[1]["name"]).to eq live_assessment.title
          expect(alignments[1]["html_url"]).to eq ""
        end
      end

      describe "contributing_scores parameter" do
        it "contributing_scores are included in rollups" do
          outcome_assessment
          api_call(:get,
                   outcome_rollups_url(outcome_course, contributing_scores: true),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   contributing_scores: true)
          json = JSON.parse(response.body)
          score_links = json["rollups"][0]["scores"][0]["links"]
          expect(score_links["outcome"]).to be_present
          cs = score_links["contributing_scores"][0]
          expect(cs["association_id"]).to be_present
          expect(cs["association_type"]).to eq "RubricAssociation"
          expect(cs["title"]).to eq "User, outcome assignment"
          expect(cs["score"]).to be_present
        end
      end
    end

    describe "outcomes" do
      before :once do
        @outcomes = Array.new(4) do
          create_outcome_assessment(new: true)
          @outcome
        end
        @outcome_group = @course.learning_outcome_groups.create!(title: "groupage")
        @outcomes += Array.new(3) do
          create_outcome_assessment(new: true)
          @outcome
        end
      end

      it "supports multiple outcomes" do
        api_call(:get,
                 outcome_rollups_url(outcome_course),
                 controller: "outcome_results",
                 action: "rollups",
                 format: "json",
                 course_id: outcome_course.id.to_s)
        json = JSON.parse(response.body)
        expect(json["rollups"].size).to eq 1
        rollup = json["rollups"][0]
        expect(rollup["scores"].size).to eq 7
      end

      it "filters by outcome id" do
        outcome_ids = @outcomes[3..4].map(&:id).sort
        api_call(:get,
                 outcome_rollups_url(outcome_course, outcome_ids: outcome_ids.join(","), include: ["outcomes"]),
                 controller: "outcome_results",
                 action: "rollups",
                 format: "json",
                 course_id: outcome_course.id.to_s,
                 outcome_ids: outcome_ids.join(","),
                 include: ["outcomes"])
        json = JSON.parse(response.body)
        expect(json["linked"]["outcomes"].size).to eq outcome_ids.length
        expect(json["linked"]["outcomes"].pluck("id").sort).to eq outcome_ids
        rollup = json["rollups"][0]
        expect(rollup["scores"].size).to eq outcome_ids.length
      end

      it "filters by outcome group id" do
        outcome_ids = @outcome_group.child_outcome_links.map(&:content_id).sort
        api_call(:get,
                 outcome_rollups_url(outcome_course, outcome_group_id: @outcome_group.id, include: ["outcomes"]),
                 controller: "outcome_results",
                 action: "rollups",
                 format: "json",
                 course_id: outcome_course.id.to_s,
                 outcome_group_id: @outcome_group.id,
                 include: ["outcomes"])
        json = JSON.parse(response.body)
        expect(json["linked"]["outcomes"].size).to eq outcome_ids.length
        expect(json["linked"]["outcomes"].pluck("id").sort).to eq outcome_ids
        rollup = json["rollups"][0]
        expect(rollup["scores"].size).to eq outcome_ids.length
      end
    end

    describe "aggregate response" do
      it "returns an aggregate json api structure" do
        outcome_result
        api_call(:get,
                 outcome_rollups_url(outcome_course, aggregate: "course"),
                 controller: "outcome_results",
                 action: "rollups",
                 format: "json",
                 course_id: outcome_course.id.to_s,
                 aggregate: "course")
        json = JSON.parse(response.body)
        expect(json.keys.sort).to eq %w[rollups]
        expect(json["rollups"].size).to eq 1
        json["rollups"].each do |rollup|
          expect(rollup.keys.sort).to eq %w[links scores]
          expect(rollup["links"]["course"]).to eq @course.id.to_s
          expect(rollup["scores"].size).to eq 1
          rollup["scores"].each do |score|
            expect(score.keys.sort).to eq %w[count hide_points links score submitted_at title]
            expect(score["count"]).to eq 1
            expect(score["score"]).to eq first_outcome_rating[:points]
            expect(score["links"].keys.sort).to eq %w[outcome]
          end
        end
      end

      describe "user_ids parameter" do
        it "restricts aggregate to specified users" do
          outcome_students
          #  rollups api requires that user_ids is an array
          student_id_str = outcome_students[0..1].map { |u| u.id.to_s }
          @user = @teacher
          api_call(:get,
                   outcome_rollups_url(outcome_course, aggregate: "course", user_ids: student_id_str),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   aggregate: "course",
                   user_ids: student_id_str)
          json = JSON.parse(response.body)
          expect(json.keys.sort).to eq %w[rollups]
          expect(json["rollups"].size).to eq 1
          json["rollups"].each do |rollup|
            expect(rollup.keys.sort).to eq %w[links scores]
            expect(rollup["links"]["course"]).to eq @course.id.to_s
            expect(rollup["scores"].size).to eq 1
            rollup["scores"].each do |score|
              expect(score.keys.sort).to eq %w[count hide_points links score submitted_at title]
              expect(score["count"]).to eq 2
              expect(score["score"]).to eq 0.5
              expect(score["links"].keys.sort).to eq %w[outcome]
            end
          end
        end
      end

      describe "section_id parameter" do
        it "restricts aggregate to the specified section" do
          sectioned_outcome_students
          @user = @teacher
          api_call(:get,
                   outcome_rollups_url(outcome_course, aggregate: "course", section_id: outcome_course_sections[0].id),
                   controller: "outcome_results",
                   action: "rollups",
                   format: "json",
                   course_id: outcome_course.id.to_s,
                   aggregate: "course",
                   section_id: outcome_course_sections[0].id.to_s)
          json = JSON.parse(response.body)
          expect(json.keys.sort).to eq %w[rollups]
          expect(json["rollups"].size).to eq 1
          json["rollups"].each do |rollup|
            expect(rollup.keys.sort).to eq %w[links scores]
            expect(rollup["links"]["course"]).to eq outcome_course.id.to_s
            expect(rollup["scores"].size).to eq 1
            rollup["scores"].each do |score|
              expect(score.keys.sort).to eq %w[count hide_points links score submitted_at title]
              expect(score["count"]).to eq outcome_course_sections[0].enrollments.count
              expect(score["score"]).to eq 1
              expect(score["links"].keys.sort).to eq %w[outcome]
            end
          end
        end
      end
    end
  end

  describe "index" do
    # the filtering and inclusion logic is shared with the rollup endpoint, so we don't retest it here
    # we test some of that logic that is more specifically useful to the index endpoint
    it "side loads alignments" do
      outcome_assessment
      api_call(:get,
               outcome_results_url(outcome_course, include: ["alignments"]),
               controller: "outcome_results",
               action: "index",
               format: "json",
               course_id: outcome_course.id.to_s,
               include: ["alignments"])
      json = JSON.parse(response.body)
      expect(json["linked"]).to be_present
      expect(json["linked"]["alignments"]).to be_present
      expect(json["linked"]["alignments"][0]["id"]).to eq outcome_assignment.asset_string
    end

    it "side loads assignments" do
      outcome_assessment
      api_call(:get,
               outcome_results_url(outcome_course, include: ["assignments"]),
               controller: "outcome_results",
               action: "index",
               format: "json",
               course_id: outcome_course.id.to_s,
               include: ["assignments"])
      json = JSON.parse(response.body)
      expect(json["linked"]).to be_present
      expect(json["linked"]["assignments"]).to be_present
      expect(json["linked"]["assignments"][0]["id"]).to eq outcome_assignment.asset_string
    end

    it "returns outcome results" do
      outcome_assessment
      api_call(:get,
               outcome_results_url(outcome_course),
               controller: "outcome_results",
               action: "index",
               format: "json",
               course_id: outcome_course.id.to_s)
      json = JSON.parse(response.body)
      expect(json["outcome_results"]).to be_present
      expect(json["outcome_results"][0]["id"]).to eq outcome_result.id
      expect(json["outcome_results"][0]["score"]).to eq outcome_result.score
      expect(json["outcome_results"][0]["links"]["learning_outcome"]).to eq outcome_object.id.to_s
      expect(json["outcome_results"][0]["links"]["alignment"]).to eq outcome_assignment.asset_string
      expect(json["outcome_results"][0]["links"]["user"]).to eq outcome_student.id.to_s
    end
  end

  describe "sharding" do
    specs_require_sharding

    it "returns results for users on multiple shards" do
      student = outcome_student
      outcome_assessment
      student2 = @shard2.activate { User.create!(name: "outofshard") }
      @course.enroll_student(student2, enrollment_state: "active")
      create_outcome_assessment(student: student2)
      @user = @teacher

      api_call(:get,
               outcome_rollups_url(outcome_course),
               controller: "outcome_results",
               action: "rollups",
               format: "json",
               course_id: outcome_course.id.to_s)
      json = JSON.parse(response.body)
      expect(json.keys.sort).to eq %w[meta rollups]
      expect(json["rollups"].size).to eq 2
      expect(json["rollups"].collect { |x| x["links"]["user"] }.sort).to eq [student.id.to_s, student2.id.to_s].sort
      json["rollups"].each do |rollup|
        expect(rollup.keys.sort).to eq %w[links scores]
        expect(rollup["scores"].size).to eq 1
        expect(rollup["links"].keys.sort).to eq %w[section status user]
      end
    end
  end
end
