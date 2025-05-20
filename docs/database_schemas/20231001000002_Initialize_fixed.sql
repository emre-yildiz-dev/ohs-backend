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

-- 1. ENUMS
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

CREATE TYPE training_material_type AS ENUM ( -- Added from previous good design
    'video',
    'pdf',
    'slides',
    'other'
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

CREATE TYPE risk_analysis_check_status AS ENUM ( -- Added missing enum
    'draft',
    'submitted',
    'in_review',
    'completed',
    'archived'
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

CREATE TYPE chat_session_type AS ENUM (
    'training_session',
    'appointment_session'
);

-- 2. CORE TABLES

CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    owner_user_id UUID, -- REFERENCES users(id) ON DELETE SET NULL (Forward reference, add later)
    max_companies INTEGER DEFAULT 10,
    max_users_per_company INTEGER DEFAULT 100,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_tenants_for_super_admin ON tenants FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_tenants_for_super_admin ON tenants FOR ALL
    USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY select_own_tenant_for_tenant_members ON tenants FOR SELECT
    USING (id = current_setting('app.current_tenant_id', true)::uuid AND
           (get_current_user_roles() && ARRAY['tenant_admin', 'ohs_specialist', 'doctor', 'employee']::text[])
    );
CREATE POLICY update_own_tenant_for_tenant_admin ON tenants FOR UPDATE
    USING (id = current_setting('app.current_tenant_id', true)::uuid AND
           'tenant_admin' = ANY(get_current_user_roles()));


CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    status company_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_companies_for_super_admin ON companies FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_companies_for_tenant_admin ON companies FOR ALL
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
CREATE POLICY select_companies_for_associated_personnel ON companies FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            (id = current_setting('app.current_company_id', true)::uuid AND 'employee' = ANY(get_current_user_roles())) OR
            ('ohs_specialist' = ANY(get_current_user_roles()) AND EXISTS (
                SELECT 1 FROM ohs_specialist_company_assignments osca
                WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = companies.id
            )) OR
            ('doctor' = ANY(get_current_user_roles()) AND EXISTS (
                SELECT 1 FROM doctor_company_assignments dca
                WHERE dca.doctor_user_id = current_setting('app.current_user_id', true)::uuid AND dca.company_id = companies.id
            ))
        )
    );


CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES tenants(id) ON DELETE SET NULL, -- Null for SuperAdmins
    company_id UUID REFERENCES companies(id) ON DELETE SET NULL, -- Primarily for Employees
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    status user_status NOT NULL DEFAULT 'pending',
    expo_push_token TEXT,
    password_reset_token TEXT,
    password_reset_expires_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_user ON users FOR SELECT
    USING (id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY update_own_user ON users FOR UPDATE -- Users can update their own (limited fields usually handled by app)
    USING (id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY manage_users_for_super_admin ON users FOR ALL -- SuperAdmins can manage all users
    USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_users_for_tenant_admin ON users FOR ALL -- TenantAdmins can manage users in their tenant
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
-- OHS can view users in companies they are assigned to (e.g., for managing employees list)
CREATE POLICY select_users_for_ohs_specialist ON users FOR SELECT
    USING (
        'ohs_specialist' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM ohs_specialist_company_assignments osca
            WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = users.company_id
        )
    );
-- Add FK for tenants.owner_user_id
ALTER TABLE tenants ADD CONSTRAINT fk_tenants_owner_user FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE SET NULL;


CREATE TABLE user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(20), -- Increased size
    phone_number TEXT UNIQUE, -- Can be NULL initially
    profile_picture_url TEXT,
    -- company_id here is denormalized for employee profiles, primarily for display.
    -- The authoritative link is users.company_id for employees.
    company_id UUID REFERENCES companies(id) ON DELETE SET NULL,
    department TEXT, -- Added from original requirements
    job_title TEXT,  -- Added from original requirements
    address TEXT,
    city TEXT,
    state TEXT,
    zip_code TEXT,
    country TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_user_profile ON user_profiles FOR ALL
    USING (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY view_user_profiles_for_super_admin ON user_profiles FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY view_user_profiles_for_tenant_admin ON user_profiles FOR SELECT
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        EXISTS (
            SELECT 1 FROM users u
            WHERE u.id = user_profiles.user_id AND u.tenant_id = current_setting('app.current_tenant_id', true)::uuid
        )
    );
CREATE POLICY view_user_profiles_for_ohs_specialist ON user_profiles FOR SELECT
    USING (
        'ohs_specialist' = ANY(get_current_user_roles()) AND
        EXISTS (
            SELECT 1 FROM users u
            JOIN ohs_specialist_company_assignments osca ON osca.company_id = u.company_id
            WHERE u.id = user_profiles.user_id AND
                  u.tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
                  osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid
        )
    );
CREATE POLICY view_user_profiles_for_doctor ON user_profiles FOR SELECT
    USING (
        'doctor' = ANY(get_current_user_roles()) AND
        EXISTS (
            SELECT 1 FROM users u
            JOIN doctor_company_assignments dca ON dca.company_id = u.company_id
            WHERE u.id = user_profiles.user_id AND
                  u.tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
                  dca.doctor_user_id = current_setting('app.current_user_id', true)::uuid
        )
    );
-- Employees can view profiles of OHS and Doctors in their tenant (for booking)
CREATE POLICY view_professional_profiles_for_employee ON user_profiles FOR SELECT
    USING (
        'employee' = ANY(get_current_user_roles()) AND
        EXISTS (
            SELECT 1 FROM users u_target
            JOIN user_tenant_context_roles utcr ON utcr.user_id = u_target.id
            WHERE u_target.id = user_profiles.user_id
              AND u_target.tenant_id = current_setting('app.current_tenant_id', true)::uuid
              AND utcr.role IN ('ohs_specialist', 'doctor')
        )
    );


CREATE TABLE user_tenant_context_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role user_role NOT NULL,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE, -- Null for SUPER_ADMIN
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE, -- Relevant for EMPLOYEE, or specific professional assignments
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, role, tenant_id, company_id)
);
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


CREATE TABLE company_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID UNIQUE NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    -- name TEXT NOT NULL, -- Name is in companies table
    -- description TEXT, -- Description is in companies table
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
CREATE POLICY view_company_profiles_for_super_admin ON company_profiles FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY manage_company_profiles_for_tenant_admin ON company_profiles FOR ALL
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        EXISTS (
            SELECT 1 FROM companies c
            WHERE c.id = company_profiles.company_id AND c.tenant_id = current_setting('app.current_tenant_id', true)::uuid
        )
    );
-- Employees, OHS, Doctors can see profile of companies they are associated with
CREATE POLICY view_associated_company_profiles ON company_profiles FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM companies c
            WHERE c.id = company_profiles.company_id AND c.tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
            (
                (c.id = current_setting('app.current_company_id', true)::uuid AND 'employee' = ANY(get_current_user_roles())) OR
                ('ohs_specialist' = ANY(get_current_user_roles()) AND EXISTS (
                    SELECT 1 FROM ohs_specialist_company_assignments osca
                    WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = c.id
                )) OR
                ('doctor' = ANY(get_current_user_roles()) AND EXISTS (
                    SELECT 1 FROM doctor_company_assignments dca
                    WHERE dca.doctor_user_id = current_setting('app.current_user_id', true)::uuid AND dca.company_id = c.id
                ))
            )
        )
    );


CREATE TABLE ohs_specialist_company_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ohs_specialist_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized for RLS, derived from company
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (ohs_specialist_user_id, company_id)
);
ALTER TABLE ohs_specialist_company_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_ohs_assignments_for_tenant_admin ON ohs_specialist_company_assignments FOR ALL
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
CREATE POLICY view_own_ohs_assignments ON ohs_specialist_company_assignments FOR SELECT
    USING (
        ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND
        'ohs_specialist' = ANY(get_current_user_roles())
    );


CREATE TABLE doctor_company_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized for RLS
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (doctor_user_id, company_id)
);
ALTER TABLE doctor_company_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_doctor_assignments_for_tenant_admin ON doctor_company_assignments FOR ALL
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
CREATE POLICY view_own_doctor_assignments ON doctor_company_assignments FOR SELECT
    USING (
        doctor_user_id = current_setting('app.current_user_id', true)::uuid AND
        'doctor' = ANY(get_current_user_roles())
    );


CREATE TABLE professional_availabilities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    professional_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist or Doctor
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (end_time > start_time)
);
ALTER TABLE professional_availabilities ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_availabilities ON professional_availabilities FOR ALL
    USING (
        professional_user_id = current_setting('app.current_user_id', true)::uuid AND
        (get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[]) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid -- Professionals operate within their tenant
    );
CREATE POLICY view_availabilities_for_tenant_members ON professional_availabilities FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_availabilities_for_super_admin ON professional_availabilities FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


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
    call_session_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (end_time > start_time)
);
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_appointments_for_participants ON appointments FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            (employee_user_id = current_setting('app.current_user_id', true)::uuid AND 'employee' = ANY(get_current_user_roles())) OR
            (professional_user_id = current_setting('app.current_user_id', true)::uuid AND (get_current_user_roles() && ARRAY['ohs_specialist', 'doctor']::text[]))
        )
    );
CREATE POLICY view_appointments_for_tenant_admin ON appointments FOR SELECT
    USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_appointments_for_super_admin ON appointments FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
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
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    training_type training_type NOT NULL DEFAULT 'live_webinar',
    status training_status NOT NULL DEFAULT 'scheduled',
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    stream_details JSONB,
    max_participants INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE training_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_training_sessions_for_host_or_admin ON training_sessions FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('ohs_specialist' = ANY(get_current_user_roles()) AND host_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('tenant_admin' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_training_sessions_for_tenant_members ON training_sessions FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_sessions_for_super_admin ON training_sessions FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE training_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    uploader_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    training_session_id UUID REFERENCES training_sessions(id) ON DELETE SET NULL, -- Can be general material
    title TEXT NOT NULL,
    description TEXT,
    material_type training_material_type NOT NULL,
    file_s3_key TEXT NOT NULL,
    file_size_bytes BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE training_materials ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_training_materials_for_uploader_or_admin ON training_materials FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            (('ohs_specialist' = ANY(get_current_user_roles()) OR 'doctor' = ANY(get_current_user_roles())) AND uploader_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('tenant_admin' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_training_materials_for_tenant_members ON training_materials FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_materials_for_super_admin ON training_materials FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE training_enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    employee_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    status participant_status NOT NULL DEFAULT 'registered',
    enrolled_at TIMESTAMPTZ DEFAULT NOW(),
    attended BOOLEAN DEFAULT FALSE, -- Can be derived from status='attended' or 'completed'
    completion_date TIMESTAMPTZ,
    certificate_s3_key TEXT,
    feedback_rating SMALLINT,
    feedback_text TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (training_session_id, employee_user_id)
);
ALTER TABLE training_enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_enrollment_for_employee ON training_enrollments FOR ALL
    USING (
        'employee' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        employee_user_id = current_setting('app.current_user_id', true)::uuid
    );
CREATE POLICY manage_enrollments_for_host_or_admin ON training_enrollments FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('tenant_admin' = ANY(get_current_user_roles())) OR
            EXISTS (SELECT 1 FROM training_sessions ts WHERE ts.id = training_enrollments.training_session_id AND ts.host_user_id = current_setting('app.current_user_id', true)::uuid AND 'ohs_specialist' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_enrollments_for_super_admin ON training_enrollments FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE training_quizzes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    created_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE training_quizzes ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_quizzes_for_creator_or_admin ON training_quizzes FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            (('ohs_specialist' = ANY(get_current_user_roles()) OR 'doctor' = ANY(get_current_user_roles())) AND created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('tenant_admin' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_quizzes_for_tenant_members ON training_quizzes FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_quizzes_for_super_admin ON training_quizzes FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE quiz_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID NOT NULL REFERENCES training_quizzes(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized
    question_text TEXT NOT NULL,
    question_type TEXT NOT NULL, -- e.g., 'MULTIPLE_CHOICE', 'SINGLE_CHOICE'
    options JSONB,
    correct_answer_key TEXT, -- or JSONB for multiple correct answers
    points INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE quiz_questions ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_quiz_questions_for_quiz_owner_or_admin ON quiz_questions FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM training_quizzes tq
            WHERE tq.id = quiz_questions.quiz_id AND
            (
                (('ohs_specialist' = ANY(get_current_user_roles()) OR 'doctor' = ANY(get_current_user_roles())) AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
                ('tenant_admin' = ANY(get_current_user_roles()))
            )
        )
    );
CREATE POLICY view_quiz_questions_for_tenant_members ON quiz_questions FOR SELECT -- If they are enrolled in the training/quiz
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM training_quizzes tq
            JOIN training_enrollments te ON te.training_session_id = tq.training_session_id
            WHERE tq.id = quiz_questions.quiz_id AND te.employee_user_id = current_setting('app.current_user_id', true)::uuid
        )
    );
CREATE POLICY view_quiz_questions_for_super_admin ON quiz_questions FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE quiz_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID NOT NULL REFERENCES training_quizzes(id) ON DELETE CASCADE,
    enrollment_id UUID UNIQUE REFERENCES training_enrollments(id) ON DELETE CASCADE, -- Link to specific enrollment
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
ALTER TABLE quiz_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_quiz_attempt ON quiz_attempts FOR ALL
    USING (
        'employee' = ANY(get_current_user_roles()) AND
        employee_user_id = current_setting('app.current_user_id', true)::uuid AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
CREATE POLICY view_quiz_attempts_for_quiz_owner_or_admin ON quiz_attempts FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM training_quizzes tq
            WHERE tq.id = quiz_attempts.quiz_id AND
            (
                (('ohs_specialist' = ANY(get_current_user_roles()) OR 'doctor' = ANY(get_current_user_roles())) AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
                ('tenant_admin' = ANY(get_current_user_roles()))
            )
        )
    );
CREATE POLICY view_quiz_attempts_for_super_admin ON quiz_attempts FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE quiz_attempt_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id UUID NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES quiz_questions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized
    answer_key TEXT,
    answer_text TEXT,
    is_correct BOOLEAN,
    submitted_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE quiz_attempt_answers ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_quiz_attempt_answers ON quiz_attempt_answers FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM quiz_attempts qa
            WHERE qa.id = quiz_attempt_answers.attempt_id AND
                  qa.employee_user_id = current_setting('app.current_user_id', true)::uuid AND
                  'employee' = ANY(get_current_user_roles())
        )
    );
CREATE POLICY view_quiz_attempt_answers_for_quiz_owner_or_admin ON quiz_attempt_answers FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM quiz_attempts qa
            JOIN training_quizzes tq ON tq.id = qa.quiz_id
            WHERE qa.id = quiz_attempt_answers.attempt_id AND
            (
                (('ohs_specialist' = ANY(get_current_user_roles()) OR 'doctor' = ANY(get_current_user_roles())) AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
                ('tenant_admin' = ANY(get_current_user_roles()))
            )
        )
    );
CREATE POLICY view_quiz_attempt_answers_for_super_admin ON quiz_attempt_answers FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


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
    attachments JSONB, -- Store array of S3 keys or URLs
    assigned_to_user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- OHS Specialist
    assigned_at TIMESTAMPTZ,
    resolution_details TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE safety_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_safety_reports_for_employee ON safety_reports FOR ALL
    USING (
        reporter_user_id = current_setting('app.current_user_id', true)::uuid AND
        NOT is_anonymous AND -- Can only manage if not anonymous and reporter
        'employee' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
CREATE POLICY insert_safety_reports_for_employee ON safety_reports FOR INSERT
    WITH CHECK (
        'employee' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        company_id = current_setting('app.current_company_id', true)::uuid AND
        (is_anonymous OR reporter_user_id = current_setting('app.current_user_id', true)::uuid)
    );
CREATE POLICY manage_safety_reports_for_assigned_ohs_or_admin ON safety_reports FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('tenant_admin' = ANY(get_current_user_roles())) OR
            (
                'ohs_specialist' = ANY(get_current_user_roles()) AND
                EXISTS (
                    SELECT 1 FROM ohs_specialist_company_assignments osca
                    WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND
                          osca.company_id = safety_reports.company_id
                ) AND (assigned_to_user_id = current_setting('app.current_user_id', true)::uuid OR assigned_to_user_id IS NULL) -- Can manage if assigned or unassigned within their companies
            )
        )
    );
CREATE POLICY view_safety_reports_for_super_admin ON safety_reports FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE risk_analysis_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    creator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    structure_json JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE risk_analysis_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_risk_templates_for_creator_or_admin ON risk_analysis_templates FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('ohs_specialist' = ANY(get_current_user_roles()) AND creator_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('tenant_admin' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_risk_templates_for_tenant_members ON risk_analysis_templates FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_risk_templates_for_super_admin ON risk_analysis_templates FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE risk_analysis_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES risk_analysis_templates(id) ON DELETE CASCADE,
    checker_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status risk_analysis_check_status NOT NULL DEFAULT 'draft',
    data_json JSONB NOT NULL,
    overall_risk_score NUMERIC(5,2),
    recommendations TEXT,
    checked_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE risk_analysis_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_risk_checks_for_checker_or_admin ON risk_analysis_checks FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('tenant_admin' = ANY(get_current_user_roles())) OR
            (
                'ohs_specialist' = ANY(get_current_user_roles()) AND
                checker_user_id = current_setting('app.current_user_id', true)::uuid AND
                EXISTS (
                    SELECT 1 FROM ohs_specialist_company_assignments osca
                    WHERE osca.ohs_specialist_user_id = risk_analysis_checks.checker_user_id AND
                          osca.company_id = risk_analysis_checks.company_id
                )
            )
        )
    );
CREATE POLICY view_risk_checks_for_company_employee ON risk_analysis_checks FOR SELECT
    USING (
        'employee' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        company_id = current_setting('app.current_company_id', true)::uuid AND
        status = 'completed' -- Or other 'published' status
    );
CREATE POLICY view_risk_checks_for_super_admin ON risk_analysis_checks FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    notification_type notification_type NOT NULL,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    related_entity_id UUID,
    related_entity_type TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_notifications ON notifications FOR ALL
    USING (user_id = current_setting('app.current_user_id', true)::uuid);
-- No super_admin or tenant_admin policy to view others' notifications by default for privacy.
-- If needed for audit, specific audit log policies would be better.


CREATE TABLE call_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    appointment_id UUID UNIQUE REFERENCES appointments(id) ON DELETE SET NULL,
    initiator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_seconds INTEGER,
    mediasoup_session_info JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE call_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY view_own_call_logs ON call_logs FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (initiator_user_id = current_setting('app.current_user_id', true)::uuid OR receiver_user_id = current_setting('app.current_user_id', true)::uuid)
    );
CREATE POLICY view_call_logs_for_tenant_admin ON call_logs FOR SELECT
    USING ('tenant_admin' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_call_logs_for_super_admin ON call_logs FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE system_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID UNIQUE REFERENCES tenants(id) ON DELETE CASCADE, -- NULL for global
    setting_key TEXT NOT NULL,
    setting_value JSONB NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, setting_key)
);
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_global_settings_for_super_admin ON system_settings FOR ALL
    USING ('super_admin' = ANY(get_current_user_roles()) AND tenant_id IS NULL);
CREATE POLICY manage_tenant_settings_for_tenant_admin ON system_settings FOR ALL
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
CREATE POLICY view_settings_for_tenant_members ON system_settings FOR SELECT
    USING (
        (tenant_id = current_setting('app.current_tenant_id', true)::uuid) OR
        (tenant_id IS NULL AND NOT ('super_admin' = ANY(get_current_user_roles()))) -- Non-superadmins can see global settings
    );


-- 3. CHAT RELATED TABLES (New Section)

CREATE TABLE session_chats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    -- Link to either a training session or an appointment. Only one should be non-NULL.
    training_session_id UUID UNIQUE REFERENCES training_sessions(id) ON DELETE CASCADE,
    appointment_id UUID UNIQUE REFERENCES appointments(id) ON DELETE CASCADE,
    chat_type chat_session_type NOT NULL, -- Optional: if you want to enforce type
    is_active BOOLEAN DEFAULT TRUE, -- To disable a chat if needed
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT chk_chat_link CHECK (
        (training_session_id IS NOT NULL AND appointment_id IS NULL) OR
        (training_session_id IS NULL AND appointment_id IS NOT NULL)
    )
);
ALTER TABLE session_chats ENABLE ROW LEVEL SECURITY;

-- Policy: Participants of the training session or appointment can access the chat.
CREATE POLICY manage_session_chats_for_participants ON session_chats FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            -- Training Session Chat
            (training_session_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM training_sessions ts
                WHERE ts.id = session_chats.training_session_id AND
                (
                    -- Host can access
                    ts.host_user_id = current_setting('app.current_user_id', true)::uuid OR
                    -- Enrolled employees can access
                    EXISTS (
                        SELECT 1 FROM training_enrollments te
                        WHERE te.training_session_id = ts.id AND
                              te.employee_user_id = current_setting('app.current_user_id', true)::uuid AND
                              te.status IN ('registered', 'attended', 'completed') -- Or relevant statuses
                    )
                )
            )) OR
            -- Appointment Chat
            (appointment_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM appointments app
                WHERE app.id = session_chats.appointment_id AND
                (
                    app.employee_user_id = current_setting('app.current_user_id', true)::uuid OR
                    app.professional_user_id = current_setting('app.current_user_id', true)::uuid
                )
            ))
        )
    );

CREATE POLICY view_session_chats_for_tenant_admin ON session_chats FOR SELECT
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );

CREATE POLICY view_session_chats_for_super_admin ON session_chats FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));


CREATE TABLE chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id UUID NOT NULL REFERENCES session_chats(id) ON DELETE CASCADE,
    sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL, -- Denormalized from session_chats for RLS efficiency
    content TEXT NOT NULL,
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    -- For read receipts (more advanced, can be added later)
    -- read_by JSONB, -- e.g., {"user_id1": "timestamp", "user_id2": "timestamp"}
    is_deleted BOOLEAN DEFAULT FALSE -- For soft deletes by sender or admin
);
-- Add FK to tenants for chat_messages.tenant_id
ALTER TABLE chat_messages ADD CONSTRAINT fk_chat_messages_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- Policy: Only participants of the parent chat session can send/see messages.
-- Sender can delete their own message (soft delete).
CREATE POLICY manage_chat_messages_for_chat_participants ON chat_messages FOR ALL
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM session_chats sc
            WHERE sc.id = chat_messages.chat_id AND
            (
                -- Training Session Chat Check
                (sc.training_session_id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM training_sessions ts
                    WHERE ts.id = sc.training_session_id AND
                    (
                        ts.host_user_id = current_setting('app.current_user_id', true)::uuid OR
                        EXISTS (
                            SELECT 1 FROM training_enrollments te
                            WHERE te.training_session_id = ts.id AND
                                  te.employee_user_id = current_setting('app.current_user_id', true)::uuid AND
                                  te.status IN ('registered', 'attended', 'completed')
                        )
                    )
                )) OR
                -- Appointment Chat Check
                (sc.appointment_id IS NOT NULL AND EXISTS (
                    SELECT 1 FROM appointments app
                    WHERE app.id = sc.appointment_id AND
                    (
                        app.employee_user_id = current_setting('app.current_user_id', true)::uuid OR
                        app.professional_user_id = current_setting('app.current_user_id', true)::uuid
                    )
                ))
            )
        )
    )
    WITH CHECK ( -- For INSERT and UPDATE
        sender_user_id = current_setting('app.current_user_id', true)::uuid AND -- Can only send as self
        NOT is_deleted -- Cannot insert/update a deleted message directly through this policy
    );

-- Policy for soft-deleting own message
CREATE POLICY soft_delete_own_chat_message ON chat_messages FOR UPDATE
    USING (
        sender_user_id = current_setting('app.current_user_id', true)::uuid AND
        NOT is_deleted -- Can only soft-delete an existing non-deleted message
    )
    WITH CHECK (is_deleted = TRUE); -- The update must set is_deleted to true

-- TenantAdmins might need to moderate/view messages (e.g., compliance)
CREATE POLICY view_chat_messages_for_tenant_admin ON chat_messages FOR SELECT
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
-- TenantAdmins can also soft-delete messages for moderation
CREATE POLICY moderate_chat_messages_for_tenant_admin ON chat_messages FOR UPDATE
    USING (
        'tenant_admin' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    )
    WITH CHECK (is_deleted = TRUE); -- Can only set is_deleted to true

CREATE POLICY view_chat_messages_for_super_admin ON chat_messages FOR SELECT
    USING ('super_admin' = ANY(get_current_user_roles()));
CREATE POLICY moderate_chat_messages_for_super_admin ON chat_messages FOR UPDATE
    USING ('super_admin' = ANY(get_current_user_roles()))
    WITH CHECK (is_deleted = TRUE);

-- Indexes for Chat Tables
CREATE INDEX idx_session_chats_tenant_id ON session_chats(tenant_id);
CREATE INDEX idx_session_chats_training_session_id ON session_chats(training_session_id) WHERE training_session_id IS NOT NULL;
CREATE INDEX idx_session_chats_appointment_id ON session_chats(appointment_id) WHERE appointment_id IS NOT NULL;

CREATE INDEX idx_chat_messages_chat_id_sent_at ON chat_messages(chat_id, sent_at DESC);
CREATE INDEX idx_chat_messages_sender_user_id ON chat_messages(sender_user_id);
CREATE INDEX idx_chat_messages_tenant_id ON chat_messages(tenant_id);


-- Create Indexes for performance (largely similar to your list, with adjustments)
-- Users table
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_tenant_id ON users(tenant_id);
CREATE INDEX idx_users_company_id ON users(company_id);
CREATE INDEX idx_users_status ON users(status);

-- User Profiles table
CREATE INDEX idx_user_profiles_phone_number ON user_profiles(phone_number);

-- User Context Roles
CREATE INDEX idx_user_context_roles_user_id ON user_tenant_context_roles(user_id);
CREATE INDEX idx_user_context_roles_tenant_id ON user_tenant_context_roles(tenant_id);
CREATE INDEX idx_user_context_roles_company_id ON user_tenant_context_roles(company_id);
CREATE INDEX idx_user_context_roles_role ON user_tenant_context_roles(role);

-- Companies table
CREATE INDEX idx_companies_tenant_id ON companies(tenant_id);
CREATE INDEX idx_companies_name ON companies(name text_pattern_ops); -- For LIKE queries

-- Company Profiles table
CREATE INDEX idx_company_profiles_company_id ON company_profiles(company_id);

-- Assignment tables
CREATE INDEX idx_ohs_assignments_user_id ON ohs_specialist_company_assignments(ohs_specialist_user_id);
CREATE INDEX idx_ohs_assignments_company_id ON ohs_specialist_company_assignments(company_id);
CREATE INDEX idx_doctor_assignments_user_id ON doctor_company_assignments(doctor_user_id);
CREATE INDEX idx_doctor_assignments_company_id ON doctor_company_assignments(company_id);

-- Professional Availabilities
CREATE INDEX idx_prof_avail_professional_user_id ON professional_availabilities(professional_user_id);
CREATE INDEX idx_prof_avail_tenant_id_times ON professional_availabilities(tenant_id, start_time, end_time);

-- Appointments table
CREATE INDEX idx_appointments_tenant_id ON appointments(tenant_id);
CREATE INDEX idx_appointments_company_id ON appointments(company_id);
CREATE INDEX idx_appointments_employee_user_id ON appointments(employee_user_id);
CREATE INDEX idx_appointments_professional_user_id ON appointments(professional_user_id);
CREATE INDEX idx_appointments_start_time ON appointments(start_time);
CREATE INDEX idx_appointments_status ON appointments(status);

-- Training Sessions table
CREATE INDEX idx_training_sessions_tenant_id ON training_sessions(tenant_id);
CREATE INDEX idx_training_sessions_host_user_id ON training_sessions(host_user_id);
CREATE INDEX idx_training_sessions_start_time ON training_sessions(start_time);
CREATE INDEX idx_training_sessions_status ON training_sessions(status);

-- Training Materials table
CREATE INDEX idx_training_materials_tenant_id ON training_materials(tenant_id);
CREATE INDEX idx_training_materials_uploader_user_id ON training_materials(uploader_user_id);
CREATE INDEX idx_training_materials_session_id ON training_materials(training_session_id);
CREATE INDEX idx_training_materials_type ON training_materials(material_type);

-- Training Enrollments table
CREATE INDEX idx_training_enrollments_tenant_id ON training_enrollments(tenant_id);
CREATE INDEX idx_training_enrollments_employee_user_id ON training_enrollments(employee_user_id);
CREATE INDEX idx_training_enrollments_session_id ON training_enrollments(training_session_id);
CREATE INDEX idx_training_enrollments_status ON training_enrollments(status);

-- Training Quizzes table
CREATE INDEX idx_training_quizzes_tenant_id ON training_quizzes(tenant_id);
CREATE INDEX idx_training_quizzes_session_id ON training_quizzes(training_session_id);
CREATE INDEX idx_training_quizzes_created_by ON training_quizzes(created_by_user_id);

-- Quiz Questions table
CREATE INDEX idx_quiz_questions_quiz_id ON quiz_questions(quiz_id);

-- Quiz Attempts table
CREATE INDEX idx_quiz_attempts_tenant_id ON quiz_attempts(tenant_id);
CREATE INDEX idx_quiz_attempts_employee_user_id ON quiz_attempts(employee_user_id);
CREATE INDEX idx_quiz_attempts_quiz_id ON quiz_attempts(quiz_id);
CREATE INDEX idx_quiz_attempts_enrollment_id ON quiz_attempts(enrollment_id);

-- Quiz Attempt Answers table
CREATE INDEX idx_quiz_attempt_answers_attempt_id ON quiz_attempt_answers(attempt_id);
CREATE INDEX idx_quiz_attempt_answers_question_id ON quiz_attempt_answers(question_id);

-- Safety Reports table
CREATE INDEX idx_safety_reports_tenant_id ON safety_reports(tenant_id);
CREATE INDEX idx_safety_reports_company_id ON safety_reports(company_id);
CREATE INDEX idx_safety_reports_reporter_user_id ON safety_reports(reporter_user_id);
CREATE INDEX idx_safety_reports_status ON safety_reports(status);
CREATE INDEX idx_safety_reports_priority ON safety_reports(priority);
CREATE INDEX idx_safety_reports_assigned_to ON safety_reports(assigned_to_user_id);

-- Risk Analysis Templates table
CREATE INDEX idx_risk_analysis_templates_tenant_id ON risk_analysis_templates(tenant_id);
CREATE INDEX idx_risk_analysis_templates_creator ON risk_analysis_templates(creator_user_id);

-- Risk Analysis Checks table
CREATE INDEX idx_risk_analysis_checks_tenant_id ON risk_analysis_checks(tenant_id);
CREATE INDEX idx_risk_analysis_checks_company_id ON risk_analysis_checks(company_id);
CREATE INDEX idx_risk_analysis_checks_template_id ON risk_analysis_checks(template_id);
CREATE INDEX idx_risk_analysis_checks_checker ON risk_analysis_checks(checker_user_id);
CREATE INDEX idx_risk_analysis_checks_status ON risk_analysis_checks(status);

-- Notifications table
CREATE INDEX idx_notifications_user_id_is_read ON notifications(user_id, is_read);
CREATE INDEX idx_notifications_type ON notifications(notification_type);

-- Call Logs table
CREATE INDEX idx_call_logs_tenant_id ON call_logs(tenant_id);
CREATE INDEX idx_call_logs_appointment_id ON call_logs(appointment_id);
CREATE INDEX idx_call_logs_initiator_user_id ON call_logs(initiator_user_id);
CREATE INDEX idx_call_logs_receiver_user_id ON call_logs(receiver_user_id);
CREATE INDEX idx_call_logs_start_time ON call_logs(start_time);

-- System Settings table
CREATE INDEX idx_system_settings_key_tenant ON system_settings(setting_key, tenant_id);