# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_23_110000) do
  create_table "accounts", force: :cascade do |t|
    t.integer "code", null: false
    t.string "name", null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "nature_code"
    t.string "group_name"
    t.string "full_name"
    t.integer "fiscal_year", null: false
    t.index ["fiscal_year", "code"], name: "index_accounts_on_fiscal_year_and_code", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "annual_reports", force: :cascade do |t|
    t.integer "fiscal_year", null: false
    t.text "achievements", default: "", null: false
    t.text "other_business", default: "", null: false
    t.text "board_meetings", default: "", null: false
    t.text "general_meetings", default: "", null: false
    t.text "members_note", default: "", null: false
    t.json "member_counts"
    t.date "letter_date"
    t.date "approved_on"
    t.date "submitted_on"
    t.date "bs_published_on"
    t.string "bs_publication_place"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "resubmit_needed_on"
    t.date "resubmitted_on"
    t.index ["fiscal_year"], name: "index_annual_reports_on_fiscal_year", unique: true
  end

  create_table "article_versions", force: :cascade do |t|
    t.integer "number", null: false
    t.date "decided_on", null: false
    t.string "meeting", default: "", null: false
    t.string "resolution", default: "", null: false
    t.string "authority", default: "", null: false
    t.string "changed_articles", default: "", null: false
    t.text "reason", default: "", null: false
    t.string "source", default: "", null: false
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["number"], name: "index_article_versions_on_number", unique: true
  end

  create_table "audit_changes", force: :cascade do |t|
    t.integer "audit_operation_id", null: false
    t.string "auditable_type", null: false
    t.integer "auditable_id", null: false
    t.string "event", null: false
    t.text "changeset"
    t.text "snapshot"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "fiscal_year"
    t.index ["audit_operation_id"], name: "index_audit_changes_on_audit_operation_id"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_changes_on_auditable_type_and_auditable_id"
    t.index ["fiscal_year"], name: "index_audit_changes_on_fiscal_year"
  end

  create_table "audit_operations", force: :cascade do |t|
    t.integer "user_id"
    t.string "scope"
    t.string "kind", default: "do", null: false
    t.string "state", default: "active", null: false
    t.boolean "redoable", default: false, null: false
    t.integer "target_id"
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "reason"
    t.index ["target_id"], name: "index_audit_operations_on_target_id"
    t.index ["user_id", "scope", "kind", "state"], name: "index_audit_operations_on_user_id_and_scope_and_kind_and_state"
    t.index ["user_id"], name: "index_audit_operations_on_user_id"
  end

  create_table "balance_checks", force: :cascade do |t|
    t.integer "account_id", null: false
    t.date "checked_on"
    t.integer "actual_amount"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_balance_checks_on_account_id"
  end

  create_table "consents", force: :cascade do |t|
    t.integer "resolution_id", null: false
    t.integer "person_id", null: false
    t.date "consented_on", null: false
    t.string "via", default: "paper", null: false
    t.string "note", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_consents_on_person_id"
    t.index ["resolution_id", "person_id"], name: "index_consents_on_resolution_id_and_person_id", unique: true
    t.index ["resolution_id"], name: "index_consents_on_resolution_id"
  end

  create_table "departments", force: :cascade do |t|
    t.integer "code", null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "full_name"
    t.integer "fiscal_year", null: false
    t.index ["fiscal_year", "code"], name: "index_departments_on_fiscal_year_and_code", unique: true
  end

  create_table "filing_destination_confirmations", force: :cascade do |t|
    t.integer "filing_destination_id", null: false
    t.integer "confirmed_by_id"
    t.string "digest", null: false
    t.datetime "confirmed_at", null: false
    t.index ["confirmed_by_id"], name: "index_filing_destination_confirmations_on_confirmed_by_id"
    t.index ["filing_destination_id"], name: "idx_on_filing_destination_id_3f11b3a090"
  end

  create_table "filing_destination_searches", force: :cascade do |t|
    t.string "address", default: "", null: false
    t.string "status", default: "searching", null: false
    t.text "error_message", default: "", null: false
    t.integer "found_count", default: 0, null: false
    t.integer "requested_by_id"
    t.datetime "requested_at", null: false
    t.index ["requested_by_id"], name: "index_filing_destination_searches_on_requested_by_id"
  end

  create_table "filing_destinations", force: :cascade do |t|
    t.string "kind", null: false
    t.string "name", default: "", null: false
    t.string "addressee", default: "", null: false
    t.string "office", default: "", null: false
    t.string "address", default: "", null: false
    t.string "phone", default: "", null: false
    t.string "fax", default: "", null: false
    t.string "email", default: "", null: false
    t.string "hours", default: "", null: false
    t.string "forms_url", default: "", null: false
    t.text "source", default: "", null: false
    t.text "notes", default: "", null: false
    t.string "origin", default: "human", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_filing_destinations_on_kind"
  end

  create_table "fiscal_periods", force: :cascade do |t|
    t.integer "year", null: false
    t.date "closed_on"
    t.integer "closed_by_id"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "closed_at"
    t.index ["closed_by_id"], name: "index_fiscal_periods_on_closed_by_id"
    t.index ["year"], name: "index_fiscal_periods_on_year", unique: true
  end

  create_table "incoming_request_messages", force: :cascade do |t|
    t.integer "incoming_request_id", null: false
    t.string "role", null: false
    t.text "body", default: "", null: false
    t.text "masked_body", default: "", null: false
    t.boolean "send_attachments", default: false, null: false
    t.datetime "sent_at"
    t.json "proposal"
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incoming_request_id"], name: "index_incoming_request_messages_on_incoming_request_id"
  end

  create_table "incoming_requests", force: :cascade do |t|
    t.string "title", default: "(整理中の依頼)", null: false
    t.string "counterpart", default: "", null: false
    t.date "received_on"
    t.date "due_on"
    t.string "status", default: "open", null: false
    t.date "resolved_on"
    t.text "cover_letter"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "journal_entries", force: :cascade do |t|
    t.integer "siwake_import_id"
    t.integer "position"
    t.integer "fiscal_year", null: false
    t.date "entry_date", null: false
    t.integer "slip_number"
    t.integer "line_number", default: 1, null: false
    t.integer "debit_account_id", null: false
    t.integer "debit_department_id"
    t.integer "debit_sub_code", default: 0, null: false
    t.string "debit_sub_name", default: "", null: false
    t.integer "debit_tax_category_code", default: 0, null: false
    t.integer "debit_business_category_code", default: 0, null: false
    t.integer "debit_tax_treatment_code", default: 3, null: false
    t.integer "debit_tax_rate", default: 10, null: false
    t.integer "debit_amount", null: false
    t.integer "debit_tax_amount", default: 0, null: false
    t.integer "credit_account_id", null: false
    t.integer "credit_department_id"
    t.integer "credit_sub_code", default: 0, null: false
    t.string "credit_sub_name", default: "", null: false
    t.integer "credit_tax_category_code", default: 0, null: false
    t.integer "credit_business_category_code", default: 0, null: false
    t.integer "credit_tax_treatment_code", default: 3, null: false
    t.integer "credit_tax_rate", default: 10, null: false
    t.integer "credit_amount", null: false
    t.integer "credit_tax_amount", default: 0, null: false
    t.string "summary", default: "", null: false
    t.string "sub_summary", default: "", null: false
    t.string "memo", default: "", null: false
    t.integer "tag1", default: 0, null: false
    t.integer "tag2", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "approved_by_id"
    t.datetime "approved_at"
    t.index ["approved_by_id"], name: "index_journal_entries_on_approved_by_id"
    t.index ["credit_account_id"], name: "index_journal_entries_on_credit_account_id"
    t.index ["credit_department_id"], name: "index_journal_entries_on_credit_department_id"
    t.index ["debit_account_id"], name: "index_journal_entries_on_debit_account_id"
    t.index ["debit_department_id"], name: "index_journal_entries_on_debit_department_id"
    t.index ["entry_date"], name: "index_journal_entries_on_entry_date"
    t.index ["fiscal_year"], name: "index_journal_entries_on_fiscal_year"
    t.index ["siwake_import_id", "position"], name: "index_journal_entries_on_siwake_import_id_and_position"
    t.index ["siwake_import_id"], name: "index_journal_entries_on_siwake_import_id"
  end

  create_table "journal_entry_cancellations", force: :cascade do |t|
    t.integer "journal_entry_id", null: false
    t.integer "canceller_id"
    t.text "reason", null: false
    t.datetime "cancelled_at", null: false
    t.index ["canceller_id"], name: "index_journal_entry_cancellations_on_canceller_id"
    t.index ["journal_entry_id"], name: "index_journal_entry_cancellations_on_journal_entry_id", unique: true
  end

  create_table "journal_proposal_approvals", force: :cascade do |t|
    t.integer "journal_proposal_id", null: false
    t.integer "approver_id"
    t.integer "journal_entry_id"
    t.datetime "approved_at", null: false
    t.index ["approver_id"], name: "index_journal_proposal_approvals_on_approver_id"
    t.index ["journal_entry_id"], name: "index_journal_proposal_approvals_on_journal_entry_id"
    t.index ["journal_proposal_id"], name: "index_journal_proposal_approvals_on_journal_proposal_id", unique: true
  end

  create_table "journal_proposal_rejections", force: :cascade do |t|
    t.integer "journal_proposal_id", null: false
    t.integer "rejecter_id"
    t.datetime "rejected_at", null: false
    t.index ["journal_proposal_id"], name: "index_journal_proposal_rejections_on_journal_proposal_id", unique: true
    t.index ["rejecter_id"], name: "index_journal_proposal_rejections_on_rejecter_id"
  end

  create_table "journal_proposal_withdrawals", force: :cascade do |t|
    t.integer "journal_proposal_id", null: false
    t.datetime "withdrawn_at", null: false
    t.index ["journal_proposal_id"], name: "index_journal_proposal_withdrawals_on_journal_proposal_id", unique: true
  end

  create_table "journal_proposals", force: :cascade do |t|
    t.integer "voucher_id", null: false
    t.date "entry_date", null: false
    t.integer "debit_account_id", null: false
    t.integer "debit_department_id"
    t.integer "credit_account_id", null: false
    t.integer "credit_department_id"
    t.integer "amount", null: false
    t.string "summary", default: "", null: false
    t.string "sub_summary", default: "", null: false
    t.text "rationale", default: "", null: false
    t.string "confidence", default: "medium", null: false
    t.string "ai_model"
    t.datetime "proposed_at", null: false
    t.integer "reproposed_from_id"
    t.index ["credit_account_id"], name: "index_journal_proposals_on_credit_account_id"
    t.index ["credit_department_id"], name: "index_journal_proposals_on_credit_department_id"
    t.index ["debit_account_id"], name: "index_journal_proposals_on_debit_account_id"
    t.index ["debit_department_id"], name: "index_journal_proposals_on_debit_department_id"
    t.index ["reproposed_from_id"], name: "index_journal_proposals_on_reproposed_from_id"
    t.index ["voucher_id"], name: "index_journal_proposals_on_voucher_id"
  end

  create_table "member_applications", force: :cascade do |t|
    t.date "applied_on", null: false
    t.string "name", null: false
    t.string "name_kana", default: "", null: false
    t.string "age_group", default: "", null: false
    t.text "postal_code"
    t.text "address"
    t.text "email"
    t.text "phone"
    t.string "notice_method", default: "", null: false
    t.string "materials_method", default: "", null: false
    t.text "referral"
    t.text "help_offers"
    t.text "comments"
    t.string "source", default: "google_form", null: false
    t.string "source_key"
    t.string "status", default: "received", null: false
    t.integer "fiscal_year"
    t.date "joined_on"
    t.date "decided_on"
    t.text "reason"
    t.integer "person_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_member_applications_on_person_id"
    t.index ["source_key"], name: "index_member_applications_on_source_key", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "fiscal_year", null: false
    t.string "kind", default: "regular", null: false
    t.date "joined_on"
    t.integer "fee_amount"
    t.date "fee_paid_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fiscal_year", "person_id", "kind"], name: "index_memberships_on_fiscal_year_and_person_id_and_kind", unique: true
    t.index ["person_id"], name: "index_memberships_on_person_id"
  end

  create_table "officer_terms", force: :cascade do |t|
    t.integer "person_id", null: false
    t.string "role", null: false
    t.date "starts_on", null: false
    t.date "ends_on", null: false
    t.date "left_on"
    t.boolean "remunerated", default: false, null: false
    t.string "appointed_by", default: "", null: false
    t.text "notes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_officer_terms_on_person_id"
  end

  create_table "opening_balances", force: :cascade do |t|
    t.integer "fiscal_year", null: false
    t.integer "account_id", null: false
    t.integer "amount", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_opening_balances_on_account_id"
    t.index ["fiscal_year", "account_id"], name: "index_opening_balances_on_fiscal_year_and_account_id", unique: true
  end

  create_table "organization_years", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "fiscal_year", null: false
    t.string "name"
    t.string "name_en"
    t.string "address"
    t.string "representative_title"
    t.string "representative_name"
    t.string "phone"
    t.string "competent_authority"
    t.text "accounting_standard_note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "fiscal_year"], name: "index_organization_years_on_organization_id_and_fiscal_year", unique: true
    t.index ["organization_id"], name: "index_organization_years_on_organization_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name"
    t.string "name_en"
    t.string "address"
    t.string "representative_title"
    t.string "representative_name"
    t.date "established_on"
    t.integer "first_fiscal_year"
    t.string "competent_authority"
    t.text "accounting_standard_note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "phone"
    t.json "settings"
  end

  create_table "passkeys", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "external_id", null: false
    t.text "public_key", null: false
    t.integer "sign_count", default: 0, null: false
    t.string "name", default: "", null: false
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_passkeys_on_external_id", unique: true
    t.index ["user_id"], name: "index_passkeys_on_user_id"
  end

  create_table "people", force: :cascade do |t|
    t.string "name", null: false
    t.string "name_kana", default: "", null: false
    t.text "address"
    t.text "email"
    t.text "phone"
    t.text "notes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "person_years", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "fiscal_year", null: false
    t.string "name", null: false
    t.string "name_kana", default: "", null: false
    t.text "address"
    t.text "email"
    t.text "phone"
    t.text "notes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id", "fiscal_year"], name: "index_person_years_on_person_id_and_fiscal_year", unique: true
    t.index ["person_id"], name: "index_person_years_on_person_id"
  end

  create_table "procedure_runs", force: :cascade do |t|
    t.string "kind", null: false
    t.integer "period", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "period"], name: "index_procedure_runs_on_kind_and_period", unique: true
  end

  create_table "procedure_steps", force: :cascade do |t|
    t.integer "procedure_run_id", null: false
    t.string "key", null: false
    t.string "status", default: "open", null: false
    t.json "checks", default: {}, null: false
    t.text "note"
    t.date "completed_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["procedure_run_id", "key"], name: "index_procedure_steps_on_procedure_run_id_and_key", unique: true
    t.index ["procedure_run_id"], name: "index_procedure_steps_on_procedure_run_id"
  end

  create_table "program_activities", force: :cascade do |t|
    t.integer "annual_report_id", null: false
    t.integer "department_id", null: false
    t.text "content", default: "", null: false
    t.text "schedule", default: "", null: false
    t.text "beneficiaries", default: "", null: false
    t.text "report", default: "", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["annual_report_id", "department_id"], name: "index_program_activities_on_annual_report_id_and_department_id", unique: true
    t.index ["annual_report_id"], name: "index_program_activities_on_annual_report_id"
    t.index ["department_id"], name: "index_program_activities_on_department_id"
  end

  create_table "program_profiles", force: :cascade do |t|
    t.integer "code", null: false
    t.text "activities", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_program_profiles_on_code", unique: true
  end

  create_table "registrations", force: :cascade do |t|
    t.string "kind", null: false
    t.date "cause_on", null: false
    t.date "due_on", null: false
    t.date "registered_on"
    t.text "note", default: "", null: false
    t.integer "officer_term_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["officer_term_id"], name: "index_registrations_on_officer_term_id"
  end

  create_table "resolution_items", force: :cascade do |t|
    t.integer "resolution_id", null: false
    t.integer "position", default: 0, null: false
    t.string "kind", default: "general", null: false
    t.string "title", null: false
    t.text "content", default: "", null: false
    t.json "payload"
    t.date "applied_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resolution_id"], name: "index_resolution_items_on_resolution_id"
  end

  create_table "resolutions", force: :cascade do |t|
    t.string "body", null: false
    t.string "title", null: false
    t.date "proposed_on", null: false
    t.integer "proposer_id", null: false
    t.string "voting_method", default: "written", null: false
    t.date "held_on"
    t.string "place", default: "", null: false
    t.text "note", default: "", null: false
    t.integer "minutes_author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["minutes_author_id"], name: "index_resolutions_on_minutes_author_id"
    t.index ["proposer_id"], name: "index_resolutions_on_proposer_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "siwake_imports", force: :cascade do |t|
    t.string "filename", null: false
    t.string "sha256", null: false
    t.string "format_name"
    t.string "format_version"
    t.string "app_name"
    t.string "app_version"
    t.datetime "exported_at"
    t.string "header_line", null: false
    t.string "columns_line", null: false
    t.integer "entries_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sha256"], name: "index_siwake_imports_on_sha256", unique: true
  end

  create_table "slack_posts", force: :cascade do |t|
    t.string "key", null: false
    t.text "text", default: "", null: false
    t.datetime "posted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_slack_posts_on_key", unique: true
  end

  create_table "todos", force: :cascade do |t|
    t.integer "incoming_request_id"
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.integer "fiscal_year"
    t.string "kind", default: "screen", null: false
    t.string "assignee", default: "", null: false
    t.string "status", default: "todo", null: false
    t.string "waiting_on", default: "", null: false
    t.date "due_on"
    t.string "target", default: "", null: false
    t.text "note", default: "", null: false
    t.string "done_rule", default: "", null: false
    t.datetime "done_at"
    t.string "done_by", default: "", null: false
    t.string "done_note", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["incoming_request_id"], name: "index_todos_on_incoming_request_id"
    t.index ["status", "fiscal_year"], name: "index_todos_on_status_and_fiscal_year"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.integer "working_year"
    t.string "role", default: "clerk", null: false
    t.json "ui_prefs", default: {}, null: false
    t.string "allowed_roles", default: "clerk", null: false
    t.string "webauthn_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["webauthn_id"], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "vouchers", force: :cascade do |t|
    t.string "kind", default: "receipt", null: false
    t.date "issued_on"
    t.text "description", default: "", null: false
    t.integer "amount"
    t.string "status", default: "pending", null: false
    t.text "notes", default: "", null: false
    t.text "ai_questions", default: "", null: false
    t.string "ai_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_vouchers_on_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_changes", "audit_operations"
  add_foreign_key "audit_operations", "audit_operations", column: "target_id"
  add_foreign_key "audit_operations", "users"
  add_foreign_key "balance_checks", "accounts"
  add_foreign_key "consents", "people"
  add_foreign_key "consents", "resolutions"
  add_foreign_key "filing_destination_confirmations", "filing_destinations"
  add_foreign_key "filing_destination_confirmations", "users", column: "confirmed_by_id"
  add_foreign_key "filing_destination_searches", "users", column: "requested_by_id"
  add_foreign_key "fiscal_periods", "users", column: "closed_by_id"
  add_foreign_key "incoming_request_messages", "incoming_requests"
  add_foreign_key "journal_entries", "accounts", column: "credit_account_id"
  add_foreign_key "journal_entries", "accounts", column: "debit_account_id"
  add_foreign_key "journal_entries", "departments", column: "credit_department_id"
  add_foreign_key "journal_entries", "departments", column: "debit_department_id"
  add_foreign_key "journal_entries", "siwake_imports"
  add_foreign_key "journal_entries", "users", column: "approved_by_id"
  add_foreign_key "journal_entry_cancellations", "journal_entries"
  add_foreign_key "journal_entry_cancellations", "users", column: "canceller_id"
  add_foreign_key "journal_proposal_approvals", "journal_entries"
  add_foreign_key "journal_proposal_approvals", "journal_proposals"
  add_foreign_key "journal_proposal_approvals", "users", column: "approver_id"
  add_foreign_key "journal_proposal_rejections", "journal_proposals"
  add_foreign_key "journal_proposal_rejections", "users", column: "rejecter_id"
  add_foreign_key "journal_proposal_withdrawals", "journal_proposals"
  add_foreign_key "journal_proposals", "accounts", column: "credit_account_id"
  add_foreign_key "journal_proposals", "accounts", column: "debit_account_id"
  add_foreign_key "journal_proposals", "departments", column: "credit_department_id"
  add_foreign_key "journal_proposals", "departments", column: "debit_department_id"
  add_foreign_key "journal_proposals", "journal_proposals", column: "reproposed_from_id"
  add_foreign_key "journal_proposals", "vouchers"
  add_foreign_key "member_applications", "people"
  add_foreign_key "memberships", "people"
  add_foreign_key "officer_terms", "people"
  add_foreign_key "opening_balances", "accounts"
  add_foreign_key "organization_years", "organizations"
  add_foreign_key "passkeys", "users"
  add_foreign_key "person_years", "people"
  add_foreign_key "procedure_steps", "procedure_runs"
  add_foreign_key "program_activities", "annual_reports"
  add_foreign_key "program_activities", "departments"
  add_foreign_key "registrations", "officer_terms"
  add_foreign_key "resolution_items", "resolutions"
  add_foreign_key "resolutions", "people", column: "minutes_author_id"
  add_foreign_key "resolutions", "people", column: "proposer_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "todos", "incoming_requests"
end
