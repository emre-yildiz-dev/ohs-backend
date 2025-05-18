-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Helper functions
CREATE OR REPLACE FUNCTION get_current_user_roles()
RETURNS TEXT[] AS $$
BEGIN
    RETURN string_to_array(current_setting('app.current_user_roles', true), ',');
EXCEPTION
    WHEN UNDEFINED_OBJECT THEN
        RETURN '{}'::TEXT[];
END;
$$ LANGUAGE plpgsql STABLE;

-- 1. ENUMS (for status fields, roles, etc.)
CREATE TYPE user_role AS ENUM (
    'super_admin',
    'tenant_admin',
    'ohs_specialist',
    'doctor',
    'employee'
);

CREATE TYPE user_status AS ENUM (
    'active',
    'inactive',
    'pending',
    'suspended'
);

CREATE TYPE company_status AS ENUM (
    'active',
    'inactive',
    'suspended'
);

CREATE TYPE appointment_status AS ENUM (
    'pending',
    'confirmed',
    'cancelled_by_professional',
    'cancelled_by_employee',
    'completed',
    'no_show'
);

CREATE TYPE appointment_type AS ENUM (
    'ohs_consultation',
    'medical_checkup'
);

CREATE TYPE training_status AS ENUM (
    'scheduled',
    'in_progress',
    'completed',
    'cancelled'
);

CREATE TYPE training_type AS ENUM (
    'live_webinar',
    'recorded_video',
    'document',
    'quiz'
);

CREATE TYPE participant_status AS ENUM (
    'registered',
    'attended',
    'completed',
    'no_show'
);

CREATE TYPE report_status AS ENUM (
    'open',
    'in_review',
    'resolved',
    'archived'
);

CREATE TYPE report_priority AS ENUM (
    'low',
    'medium',
    'high',
    'critical'
);

CREATE TYPE notification_type AS ENUM (
    'appointment_reminder',
    'appointment_confirmed',
    'appointment_cancelled',
    'training_reminder',
    'training_registration',
    'training_cancelled',
    'safety_report_update',
    'system_message',
    'new_message'
);

-- 2. CORE TABLES
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- tenant_id is NULL for SuperAdmins.
    -- For other roles, this indicates the tenant they primarily belong to or operate within.
    tenant_id UUID,
    -- company_id is relevant for Employees to directly link them.
    company_id UUID,
    -- This is the user's primary role in the system.
    -- A user might have multiple functional roles within a tenant (e.g., TenantAdmin who is also an OHS Specialist).
    -- This will be handled by a separate mapping table or by application logic checking permissions.
    -- For simplicity in RLS, we can use a primary role here and refine with a user_tenant_roles table if needed.
    -- For now, let's assume this 'primary_role' helps define their broadest context.
    -- The 'app.current_user_roles' session variable will be more granular.
    -- Let's rethink this. A user can have multiple roles within a tenant.
    -- So, we'll have a user_tenant_context_roles table.
    -- The 'users' table will just store basic info.
    -- The 'tenant_id' and 'company_id' here are more like 'default' or 'primary' associations.
    -- RLS will rely more on the context roles table and session variables.
    user_profile_id UUID REFERENCES user_profiles(id),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    status user_status NOT NULL DEFAULT 'pending',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for users: Users can see their own profile. Admins/SuperAdmins can see more.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_user ON users FOR SELECT
    USING (id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY select_users_for_super_admin ON users FOR SELECT
    USING ('SUPER_ADMIN' = ANY(get_current_user_roles()));
-- TenantAdmins can see users within their tenant.
CREATE POLICY select_users_for_tenant_admin ON users FOR SELECT
    USING (
        'TENANT_ADMIN' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
-- TODO: Add policies for UPDATE (only self, or admins)

CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(10),
    phone_number TEXT UNIQUE NOT NULL,
    profile_picture_url TEXT,
    -- For employee profiles, we'll store the employee's company information.
    -- For OHS Specialists and Doctors, this will be NULL.
    company_id UUID REFERENCES companies(id),
    address TEXT,
    city TEXT,
    state TEXT,
    zip_code TEXT,
    country TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for user_profiles: Users can see their own profile. Admins/SuperAdmins can see more.
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_user_profile ON user_profiles FOR SELECT
    USING (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY select_user_profiles_for_super_admin ON user_profiles FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
-- TenantAdmins can see user profiles within their tenant.
CREATE POLICY select_user_profiles_for_tenant_admin ON user_profiles FOR SELECT
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
-- TODO: Add policies for UPDATE (only self, or admins)

CREATE TABLE user_tenant_context_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    role user_role NOT NULL,
    -- tenant_id is NULL if the role is SUPER_ADMIN (global scope)
    tenant_id UUID REFERENCES tenants(id),
    -- company_id is relevant if the role is EMPLOYEE, or if an OHS/Doctor is specifically assigned to only one company (though multi-company assignment is typical)
    -- For OHS/Doctors serving multiple companies, use a separate assignment table.
    company_id UUID, -- Can be FK to companies table later
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, role, tenant_id, company_id) -- Ensures a user doesn't have the same role in the exact same context twice
);

-- RLS for user_tenant_context_roles:
ALTER TABLE user_tenant_context_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_user_tenant_context_roles ON user_tenant_context_roles FOR SELECT
    USING (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY manage_user_tenant_context_roles_for_super_admin ON user_tenant_context_roles FOR ALL
    USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_user_tenant_context_roles_for_tenant_admin ON user_tenant_context_roles FOR ALL
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );

CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for companies: Companies can see their own profile. Admins/SuperAdmins can see more.
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_company ON companies FOR SELECT
    USING (id = current_setting('app.current_company_id', true)::uuid);
CREATE POLICY select_companies_for_super_admin ON companies FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
-- TenantAdmins can see companies within their tenant.
CREATE POLICY select_companies_for_tenant_admin ON companies FOR SELECT
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );

CREATE TABLE company_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    name TEXT NOT NULL,
    description TEXT,
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

ALTER TABLE company_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_company_profile ON company_profiles FOR SELECT
    USING (company_id = current_setting('app.current_company_id', true)::uuid);
CREATE POLICY select_company_profiles_for_super_admin ON company_profiles FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
-- TenantAdmins can see company profiles within their tenant.
CREATE POLICY select_company_profiles_for_tenant_admin ON company_profiles FOR SELECT
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );

CREATE TABLE ohs_specialist_company_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ohs_specialist_user_id UUID NOT NULL REFERENCES users(id),
    company_id UUID NOT NULL REFERENCES companies(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (ohs_specialist_user_id, company_id)
);

CREATE TABLE doctor_company_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_user_id UUID NOT NULL REFERENCES users(id),
    company_id UUID NOT NULL REFERENCES companies(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (doctor_user_id, company_id)
);

CREATE TABLE professional_availabilities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professional_user_id UUID NOT NULL REFERENCES users(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (end_time > start_time)
);

ALTER TABLE professional_availabilities ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_professional_availabilities ON professional_availabilities FOR SELECT
    USING (professional_user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY select_professional_availabilities_for_super_admin ON professional_availabilities FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));

-- TenantAdmins can see professional availabilities within their tenant.
CREATE POLICY select_professional_availabilities_for_tenant_admin ON professional_availabilities FOR SELECT
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );


CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    company_id UUID NOT NULL REFERENCES companies(id),
    employee_user_id UUID NOT NULL REFERENCES users(id),
    professional_user_id UUID NOT NULL REFERENCES users(id),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status appointment_status NOT NULL DEFAULT 'pending',
    reason_for_visit TEXT,
    notes_by_professional TEXT,
    call_session_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_appointments_for_participants ON appointments FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            (employee_user_id = current_setting('app.current_user_id', true)::uuid AND 'EMPLOYEE' = ANY(get_current_user_roles())) OR
            (professional_user_id = current_setting('app.current_user_id', true)::uuid AND (get_current_user_roles() && ARRAY['OHS_SPECIALIST', 'DOCTOR']::text[]))
        )
    );
CREATE POLICY view_appointments_for_tenant_admin ON appointments FOR SELECT
    USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
-- OHS/Doctors should only see appointments for companies they are assigned to
CREATE POLICY view_appointments_for_assigned_ohs ON appointments FOR SELECT
    USING (
        'ohs_specialist' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        professional_user_id = current_setting('app.current_user_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM ohs_specialist_company_assignments osca
            WHERE osca.ohs_specialist_user_id = appointments.professional_user_id AND osca.company_id = appointments.company_id
        )
    );
CREATE POLICY view_appointments_for_assigned_doctor ON appointments FOR SELECT
    USING (
        'doctor' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        professional_user_id = current_setting('app.current_user_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM doctor_company_assignments dca
            WHERE dca.doctor_user_id = appointments.professional_user_id AND dca.company_id = appointments.company_id
        )
    );

CREATE TABLE training_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    host_user_id UUID NOT NULL REFERENCES users(id), -- OHS Specialist
    title TEXT NOT NULL,
    description TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    stream_details JSONB, -- Could store Mediasoup room ID, etc.
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE training_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_training_sessions_for_ohs_specialist ON training_sessions FOR ALL
    USING (
        'ohs_specialist' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        host_user_id = current_setting('app.current_user_id', true)::uuid
    );
CREATE POLICY manage_training_sessions_for_tenant_admin ON training_sessions FOR ALL
    USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_sessions_for_tenant_members ON training_sessions FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE training_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    uploader_user_id UUID NOT NULL REFERENCES users(id), -- OHS Specialist
    training_session_id UUID NOT NULL REFERENCES training_sessions(id),
    title TEXT NOT NULL,
    description TEXT,
    file_url TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE training_materials ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_training_materials_for_ohs_specialist ON training_materials FOR ALL
    USING (
        'ohs_specialist' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        uploader_user_id = current_setting('app.current_user_id', true)::uuid
    );
CREATE POLICY manage_training_materials_for_tenant_admin ON training_materials FOR ALL
    USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_materials_for_tenant_members ON training_materials FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE training_enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    training_session_id UUID NOT NULL REFERENCES training_sessions(id),
    employee_user_id UUID NOT NULL REFERENCES users(id),
    company_id UUID NOT NULL REFERENCES companies(id),
    enrolled_at TIMESTAMPTZ DEFAULT NOW(),
    attended BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE training_enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_enrollment_for_employee ON training_enrollments FOR ALL
    USING (
        'employee' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        employee_user_id = current_setting('app.current_user_id', true)::uuid
    );

CREATE POLICY manage_enrollments_for_ohs_specialist_host ON training_enrollments FOR ALL
    USING (
        'ohs_specialist' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (SELECT 1 FROM training_sessions ts WHERE ts.id = training_enrollments.training_session_id AND ts.host_user_id = current_setting('app.current_user_id', true)::uuid)
    );
CREATE POLICY manage_enrollments_for_tenant_admin ON training_enrollments FOR ALL
    USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE training_quizzes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    training_session_id UUID NOT NULL REFERENCES training_sessions(id),
    title TEXT NOT NULL,
    created_by_user_id UUID NOT NULL REFERENCES users(id), -- OHS Specialist
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE training_quizzes ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_quizzes_for_ohs_or_admin ON training_quizzes FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('OHS_SPECIALIST' = ANY(get_current_user_roles()) AND created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('TENANT_ADMIN' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_quizzes_for_tenant_members ON training_quizzes FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE TABLE quiz_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID NOT NULL REFERENCES training_quizzes(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    question_text TEXT NOT NULL,
    question_type TEXT NOT NULL,
    options JSONB,
    correct_answer_key TEXT,
    points INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
-- RLS: Inherits from quiz (OHS and TenantAdmin can manage for their tenant)
ALTER TABLE quiz_questions ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_quiz_questions_for_ohs_or_admin ON quiz_questions FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM training_quizzes tq
            WHERE tq.id = quiz_questions.quiz_id AND
            (
                ('ohs_specialist' = ANY(get_current_user_roles()) AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
                ('tenant_admin' = ANY(get_current_user_roles()))
            )
        )
    );
CREATE POLICY view_quiz_questions_for_tenant_members ON quiz_questions FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE quiz_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID NOT NULL REFERENCES training_quizzes(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    employee_user_id UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE quiz_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_quiz_attempts_for_ohs_or_admin ON quiz_attempts FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('ohs_specialist' = ANY(get_current_user_roles()) AND created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('tenant_admin' = ANY(get_current_user_roles()))
        )
    );

CREATE TABLE quiz_attempt_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id UUID NOT NULL REFERENCES quiz_attempts(id),
    question_id UUID NOT NULL REFERENCES quiz_questions(id),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    answer_key TEXT,
    answer_text TEXT,
    is_correct BOOLEAN,
    submitted_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE quiz_attempt_answers ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_quiz_attempt_answers_for_ohs_or_admin ON quiz_attempt_answers FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('ohs_specialist' = ANY(get_current_user_roles()) AND created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('tenant_admin' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_quiz_attempt_answers_for_tenant_members ON quiz_attempt_answers FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE TABLE safety_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    company_id UUID NOT NULL REFERENCES companies(id),
    employee_user_id UUID NOT NULL REFERENCES users(id),
    status safety_report_status NOT NULL DEFAULT 'open',
    priority report_priority NOT NULL DEFAULT 'low',
    description TEXT,
    attachments JSONB,
    assigned_to_user_id UUID REFERENCES users(id),
    assigned_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE POLICY manage_own_safety_reports_for_employee ON safety_reports FOR ALL
    USING (
        NOT is_anonymous AND -- Cannot modify if anonymous after creation by self
        reporter_user_id = current_setting('app.current_user_id', true)::uuid AND
        'employee' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
-- Allow employee to create anonymous reports (INSERT only)
CREATE POLICY insert_safety_reports_for_employee ON safety_reports FOR INSERT
    WITH CHECK (
        'employee' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        company_id = current_setting('app.current_company_id', true)::uuid AND
        (is_anonymous OR reporter_user_id = current_setting('app.current_user_id', true)::uuid)
    );
CREATE POLICY manage_safety_reports_for_ohs_specialist ON safety_reports FOR ALL
    USING (
        'ohs_specialist' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM ohs_specialist_company_assignments osca
            WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = safety_reports.company_id
        )
    );
CREATE POLICY manage_safety_reports_for_tenant_admin ON safety_reports FOR ALL
    USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE TABLE risk_analysis_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    creator_user_id UUID NOT NULL REFERENCES users(id), -- OHS Specialist
    name TEXT NOT NULL,
    description TEXT,
    structure_json JSONB NOT NULL, -- Defines fields, sections, scoring, etc.
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE risk_analysis_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_risk_templates_for_ohs_or_admin ON risk_analysis_templates FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('ohs_specialist' = ANY(get_current_user_roles()) AND creator_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('tenant_admin' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_risk_templates_for_tenant_members ON risk_analysis_templates FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);

CREATE TABLE risk_analysis_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    company_id UUID NOT NULL REFERENCES companies(id),
    template_id UUID NOT NULL REFERENCES risk_analysis_templates(id),
    checker_user_id UUID NOT NULL REFERENCES users(id), -- OHS Specialist
    status risk_analysis_check_status NOT NULL DEFAULT 'open',
    data_json JSONB NOT NULL, -- Filled-in template data
    overall_risk_score NUMERIC(5,2),
    recommendations TEXT,
    checked_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE risk_analysis_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_risk_checks_for_ohs_specialist ON risk_analysis_checks FOR ALL
    USING (
        'ohs_specialist' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        checker_user_id = current_setting('app.current_user_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM ohs_specialist_company_assignments osca
            WHERE osca.ohs_specialist_user_id = risk_analysis_checks.checker_user_id AND osca.company_id = risk_analysis_checks.company_id
        )
    );
CREATE POLICY manage_risk_checks_for_tenant_admin ON risk_analysis_checks FOR ALL
    USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_risk_checks_for_company_employee ON risk_analysis_checks FOR SELECT -- Employees might view completed checks for their company
    USING (
        'employee' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        company_id = current_setting('app.current_company_id', true)::uuid AND
        status = 'REVIEWED' -- Or some other 'published' status
    );

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE, -- For easier filtering if needed, though user_id implies tenant
    notification_type notification_type NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    related_entity_id UUID, -- e.g., appointment_id, training_session_id
    related_entity_type TEXT, -- e.g., 'APPOINTMENT', 'TRAINING_SESSION'
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_notifications ON notifications FOR ALL
    USING (user_id = current_setting('app.current_user_id', true)::uuid);

CREATE TABLE call_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    appointment_id UUID UNIQUE REFERENCES appointments(id) ON DELETE SET NULL, -- Link to appointment if it was a scheduled call
    initiator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_seconds INTEGER, -- Calculated: EXTRACT(EPOCH FROM (end_time - start_time))
    mediasoup_session_info JSONB, -- Any relevant info from Mediasoup
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE call_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY view_own_call_logs ON call_logs FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (initiator_user_id = current_setting('app.current_user_id', true)::uuid OR receiver_user_id = current_setting('app.current_user_id', true)::uuid)
    );
CREATE POLICY view_call_logs_for_tenant_admin ON call_logs FOR SELECT
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
-- OHS/Doctors might need to see logs for calls they were part of, or for their assigned companies (more complex policy)

CREATE TABLE system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID UNIQUE REFERENCES tenants(id) ON DELETE CASCADE, -- NULL for global settings
    setting_key TEXT NOT NULL,
    setting_value JSONB NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, setting_key)
);
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_global_settings_for_super_admin ON system_settings FOR ALL
    USING ('SUPER_ADMIN' = ANY(get_current_user_roles()) AND tenant_id IS NULL);
CREATE POLICY manage_tenant_settings_for_tenant_admin ON system_settings FOR ALL
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_settings_for_tenant_members ON system_settings FOR SELECT -- Read-only for relevant settings
    USING (
        (tenant_id = current_setting('app.current_tenant_id', true)::uuid) OR
        (tenant_id IS NULL AND 'SUPER_ADMIN' != ANY(get_current_user_roles())) -- Non-superadmins can see global settings
    );

-- Create Indexes for performance
-- Users table
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_tenant_id ON users(tenant_id);
CREATE INDEX idx_users_company_id ON users(company_id);

-- User Context Roles
CREATE INDEX idx_user_context_roles_user_id ON user_context_roles(user_id);
CREATE INDEX idx_user_context_roles_tenant_id ON user_context_roles(tenant_id);
CREATE INDEX idx_user_context_roles_company_id ON user_context_roles(company_id);

-- Companies table
CREATE INDEX idx_companies_tenant_id ON companies(tenant_id);

-- Assignment tables
CREATE INDEX idx_ohs_assignments_user_id ON ohs_specialist_company_assignments(ohs_specialist_user_id);
CREATE INDEX idx_ohs_assignments_company_id ON ohs_specialist_company_assignments(company_id);
CREATE INDEX idx_doctor_assignments_user_id ON doctor_company_assignments(doctor_user_id);
CREATE INDEX idx_doctor_assignments_company_id ON doctor_company_assignments(company_id);

-- Appointments table
CREATE INDEX idx_appointments_tenant_id ON appointments(tenant_id);
CREATE INDEX idx_appointments_company_id ON appointments(company_id);
CREATE INDEX idx_appointments_employee_user_id ON appointments(employee_user_id);
CREATE INDEX idx_appointments_professional_user_id ON appointments(professional_user_id);
CREATE INDEX idx_appointments_start_time ON appointments(start_time);
CREATE INDEX idx_appointments_end_time ON appointments(end_time);

-- Training Sessions table
CREATE INDEX idx_training_sessions_tenant_id ON training_sessions(tenant_id);
CREATE INDEX idx_training_sessions_company_id ON training_sessions(company_id);
CREATE INDEX idx_training_sessions_host_user_id ON training_sessions(host_user_id);
CREATE INDEX idx_training_sessions_start_time ON training_sessions(start_time);
CREATE INDEX idx_training_sessions_end_time ON training_sessions(end_time);

-- Training Materials table
CREATE INDEX idx_training_materials_tenant_id ON training_materials(tenant_id);
CREATE INDEX idx_training_materials_uploader_user_id ON training_materials(uploader_user_id);
CREATE INDEX idx_training_materials_training_session_id ON training_materials(training_session_id);

-- Training Enrollments table
CREATE INDEX idx_training_enrollments_tenant_id ON training_enrollments(tenant_id);
CREATE INDEX idx_training_enrollments_employee_user_id ON training_enrollments(employee_user_id);
CREATE INDEX idx_training_enrollments_training_session_id ON training_enrollments(training_session_id);

-- Training Quizzes table
CREATE INDEX idx_training_quizzes_tenant_id ON training_quizzes(tenant_id);
CREATE INDEX idx_training_quizzes_training_session_id ON training_quizzes(training_session_id);
CREATE INDEX idx_training_quizzes_created_by_user_id ON training_quizzes(created_by_user_id);

-- Quiz Questions table
CREATE INDEX idx_quiz_questions_tenant_id ON quiz_questions(tenant_id);
CREATE INDEX idx_quiz_questions_quiz_id ON quiz_questions(quiz_id);

-- Quiz Attempts table
CREATE INDEX idx_quiz_attempts_tenant_id ON quiz_attempts(tenant_id);
CREATE INDEX idx_quiz_attempts_employee_user_id ON quiz_attempts(employee_user_id);
CREATE INDEX idx_quiz_attempts_quiz_id ON quiz_attempts(quiz_id);

-- Quiz Attempt Answers table
CREATE INDEX idx_quiz_attempt_answers_tenant_id ON quiz_attempt_answers(tenant_id);
CREATE INDEX idx_quiz_attempt_answers_attempt_id ON quiz_attempt_answers(attempt_id);
CREATE INDEX idx_quiz_attempt_answers_question_id ON quiz_attempt_answers(question_id);

-- Safety Reports table
CREATE INDEX idx_safety_reports_tenant_id ON safety_reports(tenant_id);
CREATE INDEX idx_safety_reports_company_id ON safety_reports(company_id);
CREATE INDEX idx_safety_reports_employee_user_id ON safety_reports(employee_user_id);
CREATE INDEX idx_safety_reports_status ON safety_reports(status);
CREATE INDEX idx_safety_reports_priority ON safety_reports(priority);

-- Risk Analysis Templates table
CREATE INDEX idx_risk_analysis_templates_tenant_id ON risk_analysis_templates(tenant_id);
CREATE INDEX idx_risk_analysis_templates_creator_user_id ON risk_analysis_templates(creator_user_id);

-- Risk Analysis Checks table
CREATE INDEX idx_risk_analysis_checks_tenant_id ON risk_analysis_checks(tenant_id);
CREATE INDEX idx_risk_analysis_checks_company_id ON risk_analysis_checks(company_id);
CREATE INDEX idx_risk_analysis_checks_template_id ON risk_analysis_checks(template_id);
CREATE INDEX idx_risk_analysis_checks_checker_user_id ON risk_analysis_checks(checker_user_id);

-- Notifications table
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_tenant_id ON notifications(tenant_id);
CREATE INDEX idx_notifications_notification_type ON notifications(notification_type);
CREATE INDEX idx_notifications_related_entity_id ON notifications(related_entity_id);
CREATE INDEX idx_notifications_related_entity_type ON notifications(related_entity_type);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_read_at ON notifications(read_at);

-- Call Logs table
CREATE INDEX idx_call_logs_tenant_id ON call_logs(tenant_id);
CREATE INDEX idx_call_logs_appointment_id ON call_logs(appointment_id);
CREATE INDEX idx_call_logs_initiator_user_id ON call_logs(initiator_user_id);
CREATE INDEX idx_call_logs_receiver_user_id ON call_logs(receiver_user_id);
CREATE INDEX idx_call_logs_start_time ON call_logs(start_time);
CREATE INDEX idx_call_logs_end_time ON call_logs(end_time);

-- System Settings table
CREATE INDEX idx_system_settings_tenant_id ON system_settings(tenant_id);
CREATE INDEX idx_system_settings_setting_key ON system_settings(setting_key);