--------------------------------------------------------------------------------
-- 0. PRELIMINARIES & HELPER FUNCTIONS
--------------------------------------------------------------------------------

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Helper function to get current user roles from session variable
CREATE OR REPLACE FUNCTION get_current_user_roles()
RETURNS TEXT[] AS $$
BEGIN
    RETURN string_to_array(current_setting('app.current_user_roles', true), ',');
EXCEPTION
    WHEN UNDEFINED_OBJECT THEN
        RETURN '{}'::TEXT[]; -- Return empty array if session variable is not set
END;
$$ LANGUAGE plpgsql STABLE;

--------------------------------------------------------------------------------
-- 1. ENUMERATIONS (Custom Data Types)
--------------------------------------------------------------------------------

CREATE TYPE user_role AS ENUM (
    'super_admin', 'tenant_admin', 'ohs_specialist', 'doctor', 'employee'
);

CREATE TYPE user_status AS ENUM (
    'active', 'inactive', 'pending', 'suspended'
);

CREATE TYPE company_status AS ENUM (
    'active', 'inactive', 'suspended'
);

CREATE TYPE appointment_status AS ENUM (
    'pending', 'confirmed', 'cancelled_by_professional', 'cancelled_by_employee', 'completed', 'no_show'
);

CREATE TYPE appointment_type AS ENUM (
    'ohs_consultation', 'medical_checkup'
);

CREATE TYPE training_status AS ENUM (
    'scheduled', 'in_progress', 'completed', 'cancelled'
);

CREATE TYPE training_material_type AS ENUM (
    'video', 'pdf', 'slides', 'other'
);

CREATE TYPE training_type AS ENUM (
    'live_webinar', 'recorded_video', 'document', 'quiz'
);

CREATE TYPE participant_status AS ENUM (
    'registered', 'attended', 'completed', 'no_show'
);

CREATE TYPE report_status AS ENUM (
    'open', 'in_review', 'resolved', 'archived'
);

CREATE TYPE report_priority AS ENUM (
    'low', 'medium', 'high', 'critical'
);

CREATE TYPE risk_analysis_check_status AS ENUM (
    'draft', 'submitted', 'in_review', 'completed', 'archived'
);

CREATE TYPE notification_type AS ENUM (
    'appointment_reminder', 'appointment_confirmed', 'appointment_cancelled',
    'training_reminder', 'training_registration', 'training_cancelled',
    'safety_report_update', 'system_message', 'new_message'
);

CREATE TYPE subscription_plan_status AS ENUM (
    'active', 'deprecated', 'inactive'
);

CREATE TYPE tenant_subscription_status AS ENUM (
    'active', 'past_due', 'cancelled', 'expired', 'trialing'
);

--------------------------------------------------------------------------------
-- 2. CORE TENANCY, USER, AND COMPANY MANAGEMENT
--------------------------------------------------------------------------------

-- Tenants: Represents the OHS firms using the application
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    owner_user_id UUID, -- FK to users table, added after users table is created
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Users: All individuals interacting with the system
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE SET NULL, -- Null for SuperAdmins
    company_id UUID, -- FK to companies table, added after companies table, primarily for Employees
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    status user_status NOT NULL DEFAULT 'pending',
    password_reset_token TEXT,
    password_reset_expires_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add FK constraint from tenants.owner_user_id to users.id (AFTER users table is created)
ALTER TABLE tenants ADD CONSTRAINT fk_tenants_owner_user FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE SET NULL;

-- Companies: Client companies managed by a Tenant
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    status company_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add FK constraints from users.company_id to companies.id (AFTER companies table is created)
ALTER TABLE users ADD CONSTRAINT fk_users_company FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE SET NULL;

-- User Profiles: Detailed information about users
CREATE TABLE user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(20),
    phone_number TEXT UNIQUE, -- Globally unique phone number
    profile_picture_url TEXT,
    company_id UUID REFERENCES companies(id) ON DELETE SET NULL, -- Denormalized for employee profiles
    department TEXT,
    job_title TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    zip_code TEXT,
    country TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Tenant Context Roles: Defines roles of users within specific tenants or companies
CREATE TABLE user_tenant_context_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role user_role NOT NULL,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE, -- Null for SUPER_ADMIN
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE, -- Relevant for EMPLOYEE role or specific professional assignments
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, role, tenant_id, company_id)
);

-- Company Profiles: Detailed information about companies
CREATE TABLE company_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID UNIQUE NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    contact_email TEXT,
    contact_phone TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    zip_code TEXT,
    country TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- OHS Specialist Company Assignments: Links OHS Specialists to companies they serve
CREATE TABLE ohs_specialist_company_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ohs_specialist_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized from company.tenant_id for RLS
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (ohs_specialist_user_id, company_id)
);

-- Doctor Company Assignments: Links Doctors to companies they serve
CREATE TABLE doctor_company_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized from company.tenant_id for RLS
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (doctor_user_id, company_id)
);

--------------------------------------------------------------------------------
-- 3. SUBSCRIPTION & BILLING MODULE
--------------------------------------------------------------------------------

-- Subscription Plans: Defines different service tiers and their limits
CREATE TABLE subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT,
    price_monthly NUMERIC(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    status subscription_plan_status NOT NULL DEFAULT 'active',
    max_companies INTEGER,
    max_employees_total INTEGER,
    max_doctors INTEGER,
    max_ohs_specialists INTEGER,
    live_session_time_limit_minutes INTEGER,
    storage_limit_gb INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tenant Subscriptions: Links tenants to their active subscription plan
CREATE TABLE tenant_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL UNIQUE REFERENCES tenants(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
    status tenant_subscription_status NOT NULL DEFAULT 'trialing',
    start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_date TIMESTAMPTZ,
    trial_ends_at TIMESTAMPTZ,
    payment_gateway_customer_id TEXT,
    payment_gateway_subscription_id TEXT,
    custom_max_companies INTEGER,
    custom_max_employees_total INTEGER,
    custom_max_doctors INTEGER,
    custom_max_ohs_specialists INTEGER,
    custom_live_session_time_limit_minutes INTEGER,
    custom_storage_limit_gb INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

--------------------------------------------------------------------------------
-- 0. PRELIMINARIES & HELPER FUNCTIONS (CONTINUED - Function depends on tables above)
--------------------------------------------------------------------------------

-- Helper function to determine effective feature limits for a tenant based on their subscription
DROP FUNCTION IF EXISTS get_tenant_effective_limit(UUID, TEXT);
CREATE OR REPLACE FUNCTION get_tenant_effective_limit(
    p_tenant_id UUID,
    p_limit_type TEXT -- e.g., 'max_companies', 'max_employees_total', etc.
)
RETURNS INTEGER AS $$
DECLARE
    v_limit_value INTEGER;
    v_subscription tenant_subscriptions%ROWTYPE;
    v_plan subscription_plans%ROWTYPE;
BEGIN
    -- Get active or trialing subscription for the tenant
    SELECT * INTO v_subscription
    FROM tenant_subscriptions ts
    WHERE ts.tenant_id = p_tenant_id AND ts.status IN ('active', 'trialing')
    ORDER BY ts.start_date DESC LIMIT 1;

    IF NOT FOUND THEN
        -- No active subscription, return a restrictive default (0 means feature likely disabled)
        RETURN 0;
    END IF;

    -- Get the details of the subscribed plan
    SELECT * INTO v_plan FROM subscription_plans sp WHERE sp.id = v_subscription.plan_id;
    IF NOT FOUND THEN
        -- This should ideally not happen due to foreign key constraints
        RAISE EXCEPTION 'Subscription plan ID % not found for tenant %', v_subscription.plan_id, p_tenant_id;
        RETURN 0;
    END IF;

    -- Determine the limit: check custom overrides on the subscription first, then plan defaults
    CASE p_limit_type
        WHEN 'max_companies' THEN
            v_limit_value := COALESCE(v_subscription.custom_max_companies, v_plan.max_companies);
        WHEN 'max_employees_total' THEN
            v_limit_value := COALESCE(v_subscription.custom_max_employees_total, v_plan.max_employees_total);
        WHEN 'max_doctors' THEN
            v_limit_value := COALESCE(v_subscription.custom_max_doctors, v_plan.max_doctors);
        WHEN 'max_ohs_specialists' THEN
            v_limit_value := COALESCE(v_subscription.custom_max_ohs_specialists, v_plan.max_ohs_specialists);
        WHEN 'live_session_time_limit_minutes' THEN
            v_limit_value := COALESCE(v_subscription.custom_live_session_time_limit_minutes, v_plan.live_session_time_limit_minutes);
        WHEN 'storage_limit_gb' THEN
            v_limit_value := COALESCE(v_subscription.custom_storage_limit_gb, v_plan.storage_limit_gb);
        ELSE
            RAISE EXCEPTION 'Unknown limit type requested: %', p_limit_type;
            v_limit_value := NULL; -- Or 0, depending on desired behavior for unknown types
    END CASE;

    RETURN v_limit_value;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER; -- SECURITY DEFINER: Use with caution, ensures function can access subscription tables.


--------------------------------------------------------------------------------
-- 4. APPOINTMENT SYSTEM MODULE
--------------------------------------------------------------------------------

-- Professional Availabilities: Time slots when OHS Specialists or Doctors are available
CREATE TABLE professional_availabilities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professional_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (end_time > start_time)
);

-- Appointments: Scheduled consultations between Employees and Professionals
CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    employee_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    professional_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    appointment_type appointment_type NOT NULL DEFAULT 'ohs_consultation',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status appointment_status NOT NULL DEFAULT 'pending',
    reason_for_visit TEXT,
    notes_by_professional TEXT,
    call_session_id TEXT, -- Identifier for the RTC session
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (end_time > start_time)
);

--------------------------------------------------------------------------------
-- 5. TRAINING MODULE
--------------------------------------------------------------------------------

-- Training Sessions: Scheduled training events or courses
CREATE TABLE training_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist hosting
    title TEXT NOT NULL,
    description TEXT,
    training_type training_type NOT NULL DEFAULT 'live_webinar',
    status training_status NOT NULL DEFAULT 'scheduled',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    stream_details JSONB, -- Details for live streaming (e.g., Mediasoup room ID)
    max_participants INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Training Materials: Files and resources associated with training
CREATE TABLE training_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    uploader_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    training_session_id UUID REFERENCES training_sessions(id) ON DELETE SET NULL, -- Optional link to a specific session
    title TEXT NOT NULL,
    description TEXT,
    material_type training_material_type NOT NULL,
    file_s3_key TEXT NOT NULL, -- Key for the file in S3 storage
    file_size_bytes BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Training Enrollments: Tracks employee participation in training sessions
CREATE TABLE training_enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    employee_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    status participant_status NOT NULL DEFAULT 'registered',
    enrolled_at TIMESTAMPTZ DEFAULT NOW(),
    attended BOOLEAN DEFAULT FALSE,
    completion_date TIMESTAMPTZ,
    certificate_s3_key TEXT, -- S3 key for digital certificate
    feedback_rating SMALLINT,
    feedback_text TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (training_session_id, employee_user_id)
);

-- Training Quizzes: Quizzes associated with training sessions
CREATE TABLE training_quizzes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    created_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- User who created the quiz
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Quiz Questions: Individual questions within a quiz
CREATE TABLE quiz_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID NOT NULL REFERENCES training_quizzes(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized
    question_text TEXT NOT NULL,
    question_type TEXT NOT NULL, -- e.g., 'MULTIPLE_CHOICE', 'SINGLE_CHOICE'
    options JSONB, -- For multiple choice options
    correct_answer_key TEXT, -- Key(s) for the correct answer
    points INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Quiz Attempts: Records of employees taking quizzes
CREATE TABLE quiz_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID NOT NULL REFERENCES training_quizzes(id) ON DELETE CASCADE,
    enrollment_id UUID UNIQUE REFERENCES training_enrollments(id) ON DELETE CASCADE, -- Links attempt to specific enrollment
    employee_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE, -- Denormalized
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    score NUMERIC(5,2),
    passed BOOLEAN,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Quiz Attempt Answers: Specific answers given by employees during a quiz attempt
CREATE TABLE quiz_attempt_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id UUID NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES quiz_questions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized
    answer_key TEXT, -- Answer chosen by the user
    answer_text TEXT, -- For free-text answers
    is_correct BOOLEAN,
    submitted_at TIMESTAMPTZ DEFAULT NOW()
);

--------------------------------------------------------------------------------
-- 6. COMMUNICATION & REAL-TIME FEATURES (CALLS & CHAT)
--------------------------------------------------------------------------------

-- Call Logs: Records of audio/video call sessions
CREATE TABLE call_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    appointment_id UUID UNIQUE REFERENCES appointments(id) ON DELETE SET NULL, -- Optional link to a scheduled appointment
    initiator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_seconds INTEGER,
    mediasoup_session_info JSONB, -- Technical details from Mediasoup
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Session Chats: Represents a chat instance for a training session or appointment
CREATE TABLE session_chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    training_session_id UUID UNIQUE REFERENCES training_sessions(id) ON DELETE CASCADE,
    appointment_id UUID UNIQUE REFERENCES appointments(id) ON DELETE CASCADE,
    is_active BOOLEAN DEFAULT TRUE, -- To disable a chat if needed
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_chat_link CHECK ((training_session_id IS NOT NULL AND appointment_id IS NULL) OR (training_session_id IS NULL AND appointment_id IS NOT NULL))
);

-- Chat Messages: Individual messages within a session chat
CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES session_chats(id) ON DELETE CASCADE,
    sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized for RLS efficiency
    content TEXT NOT NULL,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    is_deleted BOOLEAN DEFAULT FALSE -- For soft deletes
);

--------------------------------------------------------------------------------
-- 7. SAFETY & RISK MANAGEMENT MODULE
--------------------------------------------------------------------------------

-- Safety Reports: Employee-submitted safety concerns or issues
CREATE TABLE safety_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    reporter_user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- Null if anonymous
    is_anonymous BOOLEAN DEFAULT FALSE,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    location_description TEXT,
    status report_status NOT NULL DEFAULT 'open',
    priority report_priority NOT NULL DEFAULT 'low',
    attachments JSONB, -- Array of S3 keys or URLs for attached files
    assigned_to_user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- OHS Specialist assigned to the report
    assigned_at TIMESTAMPTZ,
    resolution_details TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Risk Analysis Templates: Reusable templates for conducting risk analyses
CREATE TABLE risk_analysis_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    creator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist who created template
    name TEXT NOT NULL,
    description TEXT,
    structure_json JSONB NOT NULL, -- Defines the structure of the risk analysis
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Risk Analysis Checks: Instances of completed risk analyses based on templates
CREATE TABLE risk_analysis_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES risk_analysis_templates(id) ON DELETE CASCADE,
    checker_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist who performed check
    status risk_analysis_check_status NOT NULL DEFAULT 'draft',
    data_json JSONB NOT NULL, -- Filled-in data for the risk analysis
    overall_risk_score NUMERIC(5,2),
    recommendations TEXT,
    checked_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

--------------------------------------------------------------------------------
-- 8. NOTIFICATIONS MODULE
--------------------------------------------------------------------------------

-- Notifications: System-generated alerts and messages for users
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized for potential filtering
    notification_type notification_type NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    related_entity_id UUID, -- ID of the entity this notification relates to (e.g., appointment_id)
    related_entity_type TEXT, -- Type of the related entity (e.g., 'APPOINTMENT')
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User Push Tokens: Stores Expo Push Notification tokens for user devices
CREATE TABLE user_push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL, -- The Expo Push Token string
    device_name TEXT,    -- Optional, user-friendly name for the device
    last_used_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, token)
);

--------------------------------------------------------------------------------
-- 9. SYSTEM & CONFIGURATION MODULE
--------------------------------------------------------------------------------

-- System Settings: Global and tenant-specific application settings
CREATE TABLE system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID UNIQUE REFERENCES tenants(id) ON DELETE CASCADE, -- Null for global settings
    setting_key TEXT NOT NULL,
    setting_value JSONB NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, setting_key)
);

--------------------------------------------------------------------------------
-- 10. ROW LEVEL SECURITY (RLS) POLICIES
-- Grouped here for better manageability after all tables are defined.
--------------------------------------------------------------------------------

-- RLS for tenants
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_tenants_for_super_admin ON tenants FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_tenants_for_super_admin ON tenants FOR ALL USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY select_own_tenant_for_tenant_members ON tenants FOR SELECT USING (id = current_setting('app.current_tenant_id', true)::uuid AND (get_current_user_roles() && ARRAY['tenant_admin', 'ohs_specialist', 'doctor', 'employee']::text[]));
CREATE POLICY update_own_tenant_for_tenant_admin ON tenants FOR UPDATE USING (id = current_setting('app.current_tenant_id', true)::uuid AND 'tenant_admin' = ANY(get_current_user_roles())) WITH CHECK (id = current_setting('app.current_tenant_id', true)::uuid AND 'tenant_admin' = ANY(get_current_user_roles()));

-- RLS for users
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_user ON users FOR SELECT USING (id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY update_own_user ON users FOR UPDATE USING (id = current_setting('app.current_user_id', true)::uuid) WITH CHECK (id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY manage_users_for_super_admin ON users FOR ALL USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_users_for_tenant_admin ON users FOR ALL USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY select_users_for_ohs_specialist ON users FOR SELECT USING ('ohs_specialist' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid AND EXISTS (SELECT 1 FROM ohs_specialist_company_assignments osca WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = users.company_id));
-- Add similar SELECT policy for Doctors if they need to see users in their assigned companies
CREATE POLICY select_users_for_doctor ON users FOR SELECT USING ('doctor' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid AND EXISTS (SELECT 1 FROM doctor_company_assignments dca WHERE dca.doctor_user_id = current_setting('app.current_user_id', true)::uuid AND dca.company_id = users.company_id));

-- RLS for user_profiles
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_user_profile ON user_profiles FOR ALL USING (user_id = current_setting('app.current_user_id', true)::uuid) WITH CHECK (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY view_user_profiles_for_super_admin ON user_profiles FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY view_user_profiles_for_tenant_admin ON user_profiles FOR SELECT USING ('tenant_admin' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM users u WHERE u.id = user_profiles.user_id AND u.tenant_id = current_setting('app.current_tenant_id', true)::uuid));
CREATE POLICY view_user_profiles_for_ohs_specialist ON user_profiles FOR SELECT USING ('ohs_specialist' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM users u JOIN ohs_specialist_company_assignments osca ON osca.company_id = u.company_id WHERE u.id = user_profiles.user_id AND u.tenant_id = current_setting('app.current_tenant_id', true)::uuid AND osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid));
CREATE POLICY view_user_profiles_for_doctor ON user_profiles FOR SELECT USING ('doctor' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM users u JOIN doctor_company_assignments dca ON dca.company_id = u.company_id WHERE u.id = user_profiles.user_id AND u.tenant_id = current_setting('app.current_tenant_id', true)::uuid AND dca.doctor_user_id = current_setting('app.current_user_id', true)::uuid));
CREATE POLICY view_professional_profiles_for_employee ON user_profiles FOR SELECT USING ('employee' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM users u_target JOIN user_tenant_context_roles utcr ON utcr.user_id = u_target.id WHERE u_target.id = user_profiles.user_id AND u_target.tenant_id = current_setting('app.current_tenant_id', true)::uuid AND utcr.role IN ('ohs_specialist', 'doctor')));

-- RLS for companies
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_companies_for_super_admin ON companies FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_companies_for_tenant_admin ON companies FOR ALL USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY select_companies_for_associated_personnel ON companies FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND ((id = current_setting('app.current_company_id', true)::uuid AND 'employee' = ANY(get_current_user_roles())) OR ('ohs_specialist' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM ohs_specialist_company_assignments osca WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = companies.id)) OR ('doctor' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM doctor_company_assignments dca WHERE dca.doctor_user_id = current_setting('app.current_user_id', true)::uuid AND dca.company_id = companies.id))));

-- RLS for user_tenant_context_roles
ALTER TABLE user_tenant_context_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_user_tenant_context_roles ON user_tenant_context_roles FOR SELECT USING (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY manage_user_tenant_context_roles_for_super_admin ON user_tenant_context_roles FOR ALL USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_user_tenant_context_roles_for_tenant_admin ON user_tenant_context_roles FOR ALL USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

-- RLS for company_profiles
ALTER TABLE company_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY view_company_profiles_for_super_admin ON company_profiles FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_company_profiles_for_tenant_admin ON company_profiles FOR ALL USING ('tenant_admin' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM companies c WHERE c.id = company_profiles.company_id AND c.tenant_id = current_setting('app.current_tenant_id', true)::uuid)) WITH CHECK (EXISTS (SELECT 1 FROM companies c WHERE c.id = company_profiles.company_id AND c.tenant_id = current_setting('app.current_tenant_id', true)::uuid));
CREATE POLICY view_associated_company_profiles ON company_profiles FOR SELECT USING (EXISTS (SELECT 1 FROM companies c WHERE c.id = company_profiles.company_id AND c.tenant_id = current_setting('app.current_tenant_id', true)::uuid AND ((c.id = current_setting('app.current_company_id', true)::uuid AND 'employee' = ANY(get_current_user_roles())) OR ('ohs_specialist' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM ohs_specialist_company_assignments osca WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = c.id)) OR ('doctor' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM doctor_company_assignments dca WHERE dca.doctor_user_id = current_setting('app.current_user_id', true)::uuid AND dca.company_id = c.id)))));

-- RLS for ohs_specialist_company_assignments
ALTER TABLE ohs_specialist_company_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_ohs_assignments_for_tenant_admin ON ohs_specialist_company_assignments FOR ALL USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_own_ohs_assignments ON ohs_specialist_company_assignments FOR SELECT USING (ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND 'ohs_specialist' = ANY(get_current_user_roles()));

-- RLS for doctor_company_assignments
ALTER TABLE doctor_company_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_doctor_assignments_for_tenant_admin ON doctor_company_assignments FOR ALL USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_own_doctor_assignments ON doctor_company_assignments FOR SELECT USING (doctor_user_id = current_setting('app.current_user_id', true)::uuid AND 'doctor' = ANY(get_current_user_roles()));

-- RLS for subscription_plans
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_subscription_plans_for_super_admin ON subscription_plans FOR ALL USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY view_active_subscription_plans ON subscription_plans FOR SELECT USING (status = 'active' AND current_setting('app.current_user_id', true) IS NOT NULL); -- Any authenticated user can see active plans
CREATE POLICY view_own_subscribed_plan ON subscription_plans FOR SELECT USING (EXISTS (SELECT 1 FROM tenant_subscriptions ts WHERE ts.plan_id = subscription_plans.id AND ts.tenant_id = current_setting('app.current_tenant_id', true)::uuid AND ts.status IN ('active', 'trialing')));

-- RLS for tenant_subscriptions
ALTER TABLE tenant_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_tenant_subscriptions_for_super_admin ON tenant_subscriptions FOR ALL USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_own_tenant_subscription_for_tenant_admin ON tenant_subscriptions FOR ALL USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_own_tenant_subscription_for_tenant_members ON tenant_subscriptions FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

-- RLS for professional_availabilities
ALTER TABLE professional_availabilities ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_availabilities ON professional_availabilities FOR ALL USING (professional_user_id = current_setting('app.current_user_id', true)::uuid AND (get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[]) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (professional_user_id = current_setting('app.current_user_id', true)::uuid AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_availabilities_for_tenant_members ON professional_availabilities FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_availabilities_for_super_admin ON professional_availabilities FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for appointments
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
CREATE POLICY view_appointments_for_super_admin ON appointments FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_appointments_for_participants ON appointments FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND ((employee_user_id = current_setting('app.current_user_id', true)::uuid AND 'employee' = ANY(get_current_user_roles())) OR (professional_user_id = current_setting('app.current_user_id', true)::uuid AND (get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[])))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_appointments_for_tenant_admin ON appointments FOR SELECT USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_appointments_for_assigned_ohs ON appointments FOR SELECT USING ('ohs_specialist' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid AND professional_user_id = current_setting('app.current_user_id', true)::uuid AND EXISTS (SELECT 1 FROM ohs_specialist_company_assignments osca WHERE osca.ohs_specialist_user_id = appointments.professional_user_id AND osca.company_id = appointments.company_id));
CREATE POLICY view_appointments_for_assigned_doctor ON appointments FOR SELECT USING ('doctor' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid AND professional_user_id = current_setting('app.current_user_id', true)::uuid AND EXISTS (SELECT 1 FROM doctor_company_assignments dca WHERE dca.doctor_user_id = appointments.professional_user_id AND dca.company_id = appointments.company_id));

-- RLS for training_sessions
ALTER TABLE training_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_training_sessions_for_host_or_admin ON training_sessions FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND (('ohs_specialist' = ANY(get_current_user_roles()) AND host_user_id = current_setting('app.current_user_id', true)::uuid) OR ('tenant_admin' = ANY(get_current_user_roles())))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_sessions_for_tenant_members ON training_sessions FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_sessions_for_super_admin ON training_sessions FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for training_materials
ALTER TABLE training_materials ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_training_materials_for_uploader_or_admin ON training_materials FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND (((get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[]) AND uploader_user_id = current_setting('app.current_user_id', true)::uuid) OR ('tenant_admin' = ANY(get_current_user_roles())))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_materials_for_tenant_members ON training_materials FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_materials_for_super_admin ON training_materials FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for training_enrollments
ALTER TABLE training_enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_enrollment_for_employee ON training_enrollments FOR ALL USING ('employee' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid AND employee_user_id = current_setting('app.current_user_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND employee_user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY manage_enrollments_for_host_or_admin ON training_enrollments FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND (('tenant_admin' = ANY(get_current_user_roles())) OR EXISTS (SELECT 1 FROM training_sessions ts WHERE ts.id = training_enrollments.training_session_id AND ts.host_user_id = current_setting('app.current_user_id', true)::uuid AND 'ohs_specialist' = ANY(get_current_user_roles())))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_enrollments_for_super_admin ON training_enrollments FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for training_quizzes
ALTER TABLE training_quizzes ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_quizzes_for_creator_or_admin ON training_quizzes FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND (((get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[]) AND created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR ('tenant_admin' = ANY(get_current_user_roles())))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_quizzes_for_tenant_members ON training_quizzes FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_quizzes_for_super_admin ON training_quizzes FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for quiz_questions
ALTER TABLE quiz_questions ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_quiz_questions_for_quiz_owner_or_admin ON quiz_questions FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND EXISTS (SELECT 1 FROM training_quizzes tq WHERE tq.id = quiz_questions.quiz_id AND (((get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[]) AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR ('tenant_admin' = ANY(get_current_user_roles()))))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_quiz_questions_for_tenant_members ON quiz_questions FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND EXISTS (SELECT 1 FROM training_quizzes tq JOIN training_enrollments te ON te.training_session_id = tq.training_session_id WHERE tq.id = quiz_questions.quiz_id AND te.employee_user_id = current_setting('app.current_user_id', true)::uuid));
CREATE POLICY view_quiz_questions_for_super_admin ON quiz_questions FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for quiz_attempts
ALTER TABLE quiz_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_quiz_attempt ON quiz_attempts FOR ALL USING ('employee' = ANY(get_current_user_roles()) AND employee_user_id = current_setting('app.current_user_id', true)::uuid AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (employee_user_id = current_setting('app.current_user_id', true)::uuid AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_quiz_attempts_for_quiz_owner_or_admin ON quiz_attempts FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND EXISTS (SELECT 1 FROM training_quizzes tq WHERE tq.id = quiz_attempts.quiz_id AND (((get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[]) AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR ('tenant_admin' = ANY(get_current_user_roles())))));
CREATE POLICY view_quiz_attempts_for_super_admin ON quiz_attempts FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for quiz_attempt_answers
ALTER TABLE quiz_attempt_answers ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_quiz_attempt_answers ON quiz_attempt_answers FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND EXISTS (SELECT 1 FROM quiz_attempts qa WHERE qa.id = quiz_attempt_answers.attempt_id AND qa.employee_user_id = current_setting('app.current_user_id', true)::uuid AND 'employee' = ANY(get_current_user_roles()))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_quiz_attempt_answers_for_quiz_owner_or_admin ON quiz_attempt_answers FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND EXISTS (SELECT 1 FROM quiz_attempts qa JOIN training_quizzes tq ON tq.id = qa.quiz_id WHERE qa.id = quiz_attempt_answers.attempt_id AND (((get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[]) AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR ('tenant_admin' = ANY(get_current_user_roles())))));
CREATE POLICY view_quiz_attempt_answers_for_super_admin ON quiz_attempt_answers FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for call_logs
ALTER TABLE call_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY view_own_call_logs ON call_logs FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND (initiator_user_id = current_setting('app.current_user_id', true)::uuid OR receiver_user_id = current_setting('app.current_user_id', true)::uuid));
CREATE POLICY view_call_logs_for_tenant_admin ON call_logs FOR SELECT USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_call_logs_for_super_admin ON call_logs FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for session_chats
ALTER TABLE session_chats ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_session_chats_for_participants ON session_chats FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND ((training_session_id IS NOT NULL AND EXISTS (SELECT 1 FROM training_sessions ts WHERE ts.id = session_chats.training_session_id AND (ts.host_user_id = current_setting('app.current_user_id', true)::uuid OR EXISTS (SELECT 1 FROM training_enrollments te WHERE te.training_session_id = ts.id AND te.employee_user_id = current_setting('app.current_user_id', true)::uuid AND te.status IN ('registered', 'attended', 'completed'))))) OR (appointment_id IS NOT NULL AND EXISTS (SELECT 1 FROM appointments app WHERE app.id = session_chats.appointment_id AND (app.employee_user_id = current_setting('app.current_user_id', true)::uuid OR app.professional_user_id = current_setting('app.current_user_id', true)::uuid))))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_session_chats_for_tenant_admin ON session_chats FOR SELECT USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_session_chats_for_super_admin ON session_chats FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for chat_messages
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_chat_messages_for_chat_participants ON chat_messages FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND EXISTS (SELECT 1 FROM session_chats sc WHERE sc.id = chat_messages.chat_id AND ((sc.training_session_id IS NOT NULL AND EXISTS (SELECT 1 FROM training_sessions ts WHERE ts.id = sc.training_session_id AND (ts.host_user_id = current_setting('app.current_user_id', true)::uuid OR EXISTS (SELECT 1 FROM training_enrollments te WHERE te.training_session_id = ts.id AND te.employee_user_id = current_setting('app.current_user_id', true)::uuid AND te.status IN ('registered', 'attended', 'completed'))))) OR (sc.appointment_id IS NOT NULL AND EXISTS (SELECT 1 FROM appointments app WHERE app.id = sc.appointment_id AND (app.employee_user_id = current_setting('app.current_user_id', true)::uuid OR app.professional_user_id = current_setting('app.current_user_id', true)::uuid)))))) WITH CHECK (sender_user_id = current_setting('app.current_user_id', true)::uuid AND NOT is_deleted AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY soft_delete_own_chat_message ON chat_messages FOR UPDATE USING (sender_user_id = current_setting('app.current_user_id', true)::uuid AND NOT is_deleted) WITH CHECK (is_deleted = TRUE);
CREATE POLICY view_chat_messages_for_tenant_admin ON chat_messages FOR SELECT USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY moderate_chat_messages_for_tenant_admin ON chat_messages FOR UPDATE USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (is_deleted = TRUE);
CREATE POLICY view_chat_messages_for_super_admin ON chat_messages FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY moderate_chat_messages_for_super_admin ON chat_messages FOR UPDATE USING ('super_admin' = ANY(get_current_user_roles())) WITH CHECK (is_deleted = TRUE);

-- RLS for safety_reports
ALTER TABLE safety_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_safety_reports_for_employee ON safety_reports FOR ALL USING (reporter_user_id = current_setting('app.current_user_id', true)::uuid AND NOT is_anonymous AND 'employee' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (reporter_user_id = current_setting('app.current_user_id', true)::uuid AND NOT is_anonymous AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY insert_safety_reports_for_employee ON safety_reports FOR INSERT WITH CHECK ('employee' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid AND company_id = current_setting('app.current_company_id', true)::uuid AND (is_anonymous OR reporter_user_id = current_setting('app.current_user_id', true)::uuid));
CREATE POLICY manage_safety_reports_for_assigned_ohs_or_admin ON safety_reports FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND (('tenant_admin' = ANY(get_current_user_roles())) OR ('ohs_specialist' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM ohs_specialist_company_assignments osca WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = safety_reports.company_id) AND (assigned_to_user_id = current_setting('app.current_user_id', true)::uuid OR assigned_to_user_id IS NULL)))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_safety_reports_for_super_admin ON safety_reports FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for risk_analysis_templates
ALTER TABLE risk_analysis_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_risk_templates_for_creator_or_admin ON risk_analysis_templates FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND (('ohs_specialist' = ANY(get_current_user_roles()) AND creator_user_id = current_setting('app.current_user_id', true)::uuid) OR ('tenant_admin' = ANY(get_current_user_roles())))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_risk_templates_for_tenant_members ON risk_analysis_templates FOR SELECT USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_risk_templates_for_super_admin ON risk_analysis_templates FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for risk_analysis_checks
ALTER TABLE risk_analysis_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_risk_checks_for_checker_or_admin ON risk_analysis_checks FOR ALL USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid AND (('tenant_admin' = ANY(get_current_user_roles())) OR ('ohs_specialist' = ANY(get_current_user_roles()) AND checker_user_id = current_setting('app.current_user_id', true)::uuid AND EXISTS (SELECT 1 FROM ohs_specialist_company_assignments osca WHERE osca.ohs_specialist_user_id = risk_analysis_checks.checker_user_id AND osca.company_id = risk_analysis_checks.company_id)))) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_risk_checks_for_company_employee ON risk_analysis_checks FOR SELECT USING ('employee' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid AND company_id = current_setting('app.current_company_id', true)::uuid AND status = 'completed');
CREATE POLICY view_risk_checks_for_super_admin ON risk_analysis_checks FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));

-- RLS for notifications
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_notifications ON notifications FOR ALL USING (user_id = current_setting('app.current_user_id', true)::uuid) WITH CHECK (user_id = current_setting('app.current_user_id', true)::uuid);

-- RLS for user_push_tokens
ALTER TABLE user_push_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_user_push_tokens ON user_push_tokens FOR ALL USING (user_id = current_setting('app.current_user_id', true)::uuid) WITH CHECK (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY view_user_push_tokens_for_super_admin ON user_push_tokens FOR SELECT USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY view_user_push_tokens_for_tenant_admin ON user_push_tokens FOR SELECT USING ('tenant_admin' = ANY(get_current_user_roles()) AND EXISTS (SELECT 1 FROM users u WHERE u.id = user_push_tokens.user_id AND u.tenant_id = current_setting('app.current_tenant_id', true)::uuid));

-- RLS for system_settings
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_global_settings_for_super_admin ON system_settings FOR ALL USING ('super_admin' = ANY(get_current_user_roles()) AND tenant_id IS NULL) WITH CHECK (tenant_id IS NULL);
CREATE POLICY manage_tenant_settings_for_tenant_admin ON system_settings FOR ALL USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid) WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_settings_for_tenant_members ON system_settings FOR SELECT USING ((tenant_id = current_setting('app.current_tenant_id', true)::uuid) OR (tenant_id IS NULL AND NOT ('super_admin' = ANY(get_current_user_roles()))));

--------------------------------------------------------------------------------
-- 11. INDEXES
--------------------------------------------------------------------------------

-- Note: Indexes are crucial for query performance, especially with RLS.
-- This section groups all index creations for clarity.

-- Indexes for CORE TENANCY, USER, AND COMPANY MANAGEMENT
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_tenant_id ON users(tenant_id);
CREATE INDEX idx_users_company_id ON users(company_id);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_user_profiles_phone_number ON user_profiles(phone_number);
CREATE INDEX idx_user_tenant_context_roles_user_id ON user_tenant_context_roles(user_id);
CREATE INDEX idx_user_tenant_context_roles_tenant_id ON user_tenant_context_roles(tenant_id);
CREATE INDEX idx_user_tenant_context_roles_company_id ON user_tenant_context_roles(company_id);
CREATE INDEX idx_user_tenant_context_roles_role ON user_tenant_context_roles(role);
CREATE INDEX idx_companies_tenant_id ON companies(tenant_id);
CREATE INDEX idx_companies_name ON companies(name text_pattern_ops);
CREATE INDEX idx_company_profiles_company_id ON company_profiles(company_id);
CREATE INDEX idx_ohs_assignments_user_id ON ohs_specialist_company_assignments(ohs_specialist_user_id);
CREATE INDEX idx_ohs_assignments_company_id ON ohs_specialist_company_assignments(company_id);
CREATE INDEX idx_doctor_assignments_user_id ON doctor_company_assignments(doctor_user_id);
CREATE INDEX idx_doctor_assignments_company_id ON doctor_company_assignments(company_id);

-- Indexes for SUBSCRIPTION & BILLING
CREATE INDEX idx_subscription_plans_status ON subscription_plans(status);
CREATE INDEX idx_subscription_plans_price_monthly ON subscription_plans(price_monthly);
CREATE INDEX idx_tenant_subscriptions_tenant_id ON tenant_subscriptions(tenant_id);
CREATE INDEX idx_tenant_subscriptions_plan_id ON tenant_subscriptions(plan_id);
CREATE INDEX idx_tenant_subscriptions_status ON tenant_subscriptions(status);
CREATE INDEX idx_tenant_subscriptions_end_date ON tenant_subscriptions(end_date);

-- Indexes for APPOINTMENT SYSTEM
CREATE INDEX idx_prof_avail_professional_user_id ON professional_availabilities(professional_user_id);
CREATE INDEX idx_prof_avail_tenant_id_times ON professional_availabilities(tenant_id, start_time, end_time);
CREATE INDEX idx_appointments_tenant_id ON appointments(tenant_id);
CREATE INDEX idx_appointments_company_id ON appointments(company_id);
CREATE INDEX idx_appointments_employee_user_id ON appointments(employee_user_id);
CREATE INDEX idx_appointments_professional_user_id ON appointments(professional_user_id);
CREATE INDEX idx_appointments_start_time ON appointments(start_time);
CREATE INDEX idx_appointments_status ON appointments(status);

-- Indexes for TRAINING MODULE
CREATE INDEX idx_training_sessions_tenant_id ON training_sessions(tenant_id);
CREATE INDEX idx_training_sessions_host_user_id ON training_sessions(host_user_id);
CREATE INDEX idx_training_sessions_start_time ON training_sessions(start_time);
CREATE INDEX idx_training_sessions_status ON training_sessions(status);
CREATE INDEX idx_training_materials_tenant_id ON training_materials(tenant_id);
CREATE INDEX idx_training_materials_uploader_user_id ON training_materials(uploader_user_id);
CREATE INDEX idx_training_materials_session_id ON training_materials(training_session_id);
CREATE INDEX idx_training_materials_type ON training_materials(material_type);
CREATE INDEX idx_training_enrollments_tenant_id ON training_enrollments(tenant_id);
CREATE INDEX idx_training_enrollments_employee_user_id ON training_enrollments(employee_user_id);
CREATE INDEX idx_training_enrollments_session_id ON training_enrollments(training_session_id);
CREATE INDEX idx_training_enrollments_status ON training_enrollments(status);
CREATE INDEX idx_training_quizzes_tenant_id ON training_quizzes(tenant_id);
CREATE INDEX idx_training_quizzes_session_id ON training_quizzes(training_session_id);
CREATE INDEX idx_training_quizzes_created_by ON training_quizzes(created_by_user_id);
CREATE INDEX idx_quiz_questions_quiz_id ON quiz_questions(quiz_id);
CREATE INDEX idx_quiz_attempts_tenant_id ON quiz_attempts(tenant_id);
CREATE INDEX idx_quiz_attempts_employee_user_id ON quiz_attempts(employee_user_id);
CREATE INDEX idx_quiz_attempts_quiz_id ON quiz_attempts(quiz_id);
CREATE INDEX idx_quiz_attempts_enrollment_id ON quiz_attempts(enrollment_id);
CREATE INDEX idx_quiz_attempt_answers_attempt_id ON quiz_attempt_answers(attempt_id);
CREATE INDEX idx_quiz_attempt_answers_question_id ON quiz_attempt_answers(question_id);

-- Indexes for COMMUNICATION & REAL-TIME FEATURES
CREATE INDEX idx_call_logs_tenant_id ON call_logs(tenant_id);
CREATE INDEX idx_call_logs_appointment_id ON call_logs(appointment_id);
CREATE INDEX idx_call_logs_initiator_user_id ON call_logs(initiator_user_id);
CREATE INDEX idx_call_logs_receiver_user_id ON call_logs(receiver_user_id);
CREATE INDEX idx_call_logs_start_time ON call_logs(start_time);
CREATE INDEX idx_session_chats_tenant_id ON session_chats(tenant_id);
CREATE INDEX idx_session_chats_training_session_id ON session_chats(training_session_id) WHERE training_session_id IS NOT NULL;
CREATE INDEX idx_session_chats_appointment_id ON session_chats(appointment_id) WHERE appointment_id IS NOT NULL;
CREATE INDEX idx_chat_messages_chat_id_sent_at ON chat_messages(chat_id, sent_at DESC);
CREATE INDEX idx_chat_messages_sender_user_id ON chat_messages(sender_user_id);
CREATE INDEX idx_chat_messages_tenant_id ON chat_messages(tenant_id);

-- Indexes for SAFETY & RISK MANAGEMENT
CREATE INDEX idx_safety_reports_tenant_id ON safety_reports(tenant_id);
CREATE INDEX idx_safety_reports_company_id ON safety_reports(company_id);
CREATE INDEX idx_safety_reports_reporter_user_id ON safety_reports(reporter_user_id);
CREATE INDEX idx_safety_reports_status ON safety_reports(status);
CREATE INDEX idx_safety_reports_priority ON safety_reports(priority);
CREATE INDEX idx_safety_reports_assigned_to ON safety_reports(assigned_to_user_id);
CREATE INDEX idx_risk_analysis_templates_tenant_id ON risk_analysis_templates(tenant_id);
CREATE INDEX idx_risk_analysis_templates_creator ON risk_analysis_templates(creator_user_id);
CREATE INDEX idx_risk_analysis_checks_tenant_id ON risk_analysis_checks(tenant_id);
CREATE INDEX idx_risk_analysis_checks_company_id ON risk_analysis_checks(company_id);
CREATE INDEX idx_risk_analysis_checks_template_id ON risk_analysis_checks(template_id);
CREATE INDEX idx_risk_analysis_checks_checker ON risk_analysis_checks(checker_user_id);
CREATE INDEX idx_risk_analysis_checks_status ON risk_analysis_checks(status);

-- Indexes for NOTIFICATIONS
CREATE INDEX idx_notifications_user_id_is_read ON notifications(user_id, is_read);
CREATE INDEX idx_notifications_type ON notifications(notification_type);
CREATE INDEX idx_user_push_tokens_user_id ON user_push_tokens(user_id);
CREATE INDEX idx_user_push_tokens_token ON user_push_tokens(token);
CREATE INDEX idx_user_push_tokens_last_used_at ON user_push_tokens(last_used_at);

-- Indexes for SYSTEM & CONFIGURATION
CREATE INDEX idx_system_settings_key_tenant ON system_settings(setting_key, tenant_id);

--------------------------------------------------------------------------------
-- END OF SCRIPT
--------------------------------------------------------------------------------