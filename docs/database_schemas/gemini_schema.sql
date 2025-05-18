-- Enable pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Helper function to get current user roles as an array
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
    'SUPER_ADMIN',
    'TENANT_ADMIN',
    'OHS_SPECIALIST',
    'DOCTOR',
    'EMPLOYEE'
);

CREATE TYPE appointment_status AS ENUM (
    'PENDING',
    'CONFIRMED',
    'CANCELLED_BY_PROFESSIONAL',
    'CANCELLED_BY_EMPLOYEE',
    'COMPLETED',
    'NO_SHOW'
);

CREATE TYPE safety_report_status AS ENUM (
    'OPEN',
    'IN_REVIEW',
    'RESOLVED',
    'ARCHIVED'
);

CREATE TYPE training_material_type AS ENUM (
    'VIDEO',
    'PDF',
    'SLIDES',
    'OTHER'
);

CREATE TYPE notification_type AS ENUM (
    'APPOINTMENT_CONFIRMED',
    'APPOINTMENT_CANCELLED',
    'APPOINTMENT_REMINDER',
    'TRAINING_REMINDER',
    'NEW_SAFETY_REPORT',
    'SAFETY_REPORT_UPDATE',
    'GENERAL_ANNOUNCEMENT'
);

-- 2. CORE TABLES

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    full_name TEXT NOT NULL,
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

    expo_push_token TEXT, -- For push notifications
    password_reset_token TEXT,
    password_reset_expires_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
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


CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    owner_user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- The initial TenantAdmin
    max_companies INTEGER DEFAULT 10,
    max_users_per_company INTEGER DEFAULT 100,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- RLS for tenants: SuperAdmins see all. TenantAdmins see their own.
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_tenants_for_super_admin ON tenants FOR SELECT
    USING ('SUPER_ADMIN' = ANY(get_current_user_roles()));
CREATE POLICY select_own_tenant_for_tenant_members ON tenants FOR SELECT
    USING (id = current_setting('app.current_tenant_id', true)::uuid AND
           (get_current_user_roles() && ARRAY['TENANT_ADMIN', 'OHS_SPECIALIST', 'DOCTOR', 'EMPLOYEE']::text[]) -- any of these roles
    );
CREATE POLICY manage_tenants_for_super_admin ON tenants FOR ALL
    USING ('SUPER_ADMIN' = ANY(get_current_user_roles()));
CREATE POLICY update_own_tenant_for_tenant_admin ON tenants FOR UPDATE
    USING (id = current_setting('app.current_tenant_id', true)::uuid AND
           'TENANT_ADMIN' = ANY(get_current_user_roles()));


-- This table defines the roles a user has within a specific tenant or globally.
CREATE TABLE user_context_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role user_role NOT NULL,
    -- tenant_id is NULL if the role is SUPER_ADMIN (global scope)
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    -- company_id is relevant if the role is EMPLOYEE, or if an OHS/Doctor is specifically assigned to only one company (though multi-company assignment is typical)
    -- For OHS/Doctors serving multiple companies, use a separate assignment table.
    company_id UUID, -- Can be FK to companies table later
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, role, tenant_id, company_id) -- Ensures a user doesn't have the same role in the exact same context twice
);
-- RLS for user_context_roles:
ALTER TABLE user_context_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_own_user_context_roles ON user_context_roles FOR SELECT
    USING (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY manage_user_context_roles_for_super_admin ON user_context_roles FOR ALL
    USING ('SUPER_ADMIN' = ANY(get_current_user_roles()));
CREATE POLICY manage_user_context_roles_for_tenant_admin ON user_context_roles FOR ALL
    USING (
        'TENANT_ADMIN' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );


CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    address TEXT,
    contact_email TEXT,
    contact_phone TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_companies_for_super_admin ON companies FOR SELECT
    USING ('SUPER_ADMIN' = ANY(get_current_user_roles()));
CREATE POLICY manage_companies_for_tenant_admin ON companies FOR ALL
    USING (
        'TENANT_ADMIN' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
-- OHS, Doctors, Employees can see companies they are associated with.
CREATE POLICY select_companies_for_associated_personnel ON companies FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            -- Employee sees their own company
            (id = current_setting('app.current_company_id', true)::uuid AND 'EMPLOYEE' = ANY(get_current_user_roles())) OR
            -- OHS/Doctor sees companies they are assigned to
            ('OHS_SPECIALIST' = ANY(get_current_user_roles()) AND EXISTS (
                SELECT 1 FROM ohs_specialist_company_assignments osca
                WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = companies.id
            )) OR
            ('DOCTOR' = ANY(get_current_user_roles()) AND EXISTS (
                SELECT 1 FROM doctor_company_assignments dca
                WHERE dca.doctor_user_id = current_setting('app.current_user_id', true)::uuid AND dca.company_id = companies.id
            ))
        )
    );

-- Add FK constraint from users.company_id to companies.id
ALTER TABLE users
ADD CONSTRAINT fk_users_company FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE SET NULL;

-- Add FK constraint from user_context_roles.company_id to companies.id
ALTER TABLE user_context_roles
ADD CONSTRAINT fk_user_context_roles_company FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;


CREATE TABLE employee_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    -- company_id is already in users table for employees, but can be here for denormalization/clarity
    -- company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department TEXT,
    job_title TEXT,
    -- RLS: tenant_id is implicitly derived from user_id -> users.tenant_id
    -- or from company_id -> companies.tenant_id
    tenant_id UUID NOT NULL, -- Derived from user's company's tenant
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE employee_profiles ADD CONSTRAINT fk_employee_profiles_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE;
ALTER TABLE employee_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_employee_profile ON employee_profiles FOR ALL
    USING (user_id = current_setting('app.current_user_id', true)::uuid AND 'EMPLOYEE' = ANY(get_current_user_roles()));
CREATE POLICY view_employee_profiles_for_tenant_admin ON employee_profiles FOR SELECT
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_employee_profiles_for_ohs_specialist ON employee_profiles FOR SELECT
    USING (
        'OHS_SPECIALIST' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS ( -- Check if OHS is assigned to the employee's company
            SELECT 1 FROM users u
            JOIN ohs_specialist_company_assignments osca ON osca.company_id = u.company_id
            WHERE u.id = employee_profiles.user_id AND osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid
        )
    );
-- Similar policy for Doctors if they need to see employee profiles


-- OHS Specialists and Doctors can serve multiple companies within their tenant.
CREATE TABLE ohs_specialist_company_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ohs_specialist_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized for RLS, but derived from company
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (ohs_specialist_user_id, company_id)
);
ALTER TABLE ohs_specialist_company_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_ohs_assignments_for_tenant_admin ON ohs_specialist_company_assignments FOR ALL
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_own_ohs_assignments ON ohs_specialist_company_assignments FOR SELECT
    USING (ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND 'OHS_SPECIALIST' = ANY(get_current_user_roles()));


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
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_own_doctor_assignments ON doctor_company_assignments FOR SELECT
    USING (doctor_user_id = current_setting('app.current_user_id', true)::uuid AND 'DOCTOR' = ANY(get_current_user_roles()));


-- 3. APPOINTMENT SYSTEM

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
    USING (professional_user_id = current_setting('app.current_user_id', true)::uuid AND
           (get_current_user_roles() && ARRAY['OHS_SPECIALIST', 'DOCTOR']::text[]));
CREATE POLICY view_availabilities_for_tenant_members ON professional_availabilities FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE, -- Company of the employee
    employee_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    professional_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS or Doctor
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status appointment_status NOT NULL DEFAULT 'PENDING',
    reason_for_visit TEXT,
    notes_by_professional TEXT, -- Notes after the call
    call_session_id TEXT, -- For linking to Mediasoup session if needed
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (end_time > start_time)
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
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
-- OHS/Doctors should only see appointments for companies they are assigned to
CREATE POLICY view_appointments_for_assigned_ohs ON appointments FOR SELECT
    USING (
        'OHS_SPECIALIST' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        professional_user_id = current_setting('app.current_user_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM ohs_specialist_company_assignments osca
            WHERE osca.ohs_specialist_user_id = appointments.professional_user_id AND osca.company_id = appointments.company_id
        )
    );
CREATE POLICY view_appointments_for_assigned_doctor ON appointments FOR SELECT
    USING (
        'DOCTOR' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        professional_user_id = current_setting('app.current_user_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM doctor_company_assignments dca
            WHERE dca.doctor_user_id = appointments.professional_user_id AND dca.company_id = appointments.company_id
        )
    );


-- 4. TRAINING MODULE

CREATE TABLE training_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist
    title TEXT NOT NULL,
    description TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    stream_details JSONB, -- Could store Mediasoup room ID, etc.
    max_participants INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE training_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_training_sessions_for_ohs_specialist ON training_sessions FOR ALL
    USING (
        'OHS_SPECIALIST' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        host_user_id = current_setting('app.current_user_id', true)::uuid
    );
CREATE POLICY manage_training_sessions_for_tenant_admin ON training_sessions FOR ALL
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_sessions_for_tenant_members ON training_sessions FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE training_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    uploader_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist
    training_session_id UUID REFERENCES training_sessions(id) ON DELETE SET NULL, -- Optional: if material is for a specific session
    title TEXT NOT NULL,
    description TEXT,
    material_type training_material_type NOT NULL,
    file_s3_key TEXT NOT NULL, -- Key in Garage S3
    file_size_bytes BIGINT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE training_materials ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_training_materials_for_ohs_specialist ON training_materials FOR ALL
    USING (
        'OHS_SPECIALIST' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        uploader_user_id = current_setting('app.current_user_id', true)::uuid
    );
CREATE POLICY manage_training_materials_for_tenant_admin ON training_materials FOR ALL
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_training_materials_for_tenant_members ON training_materials FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE training_enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    employee_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE, -- Employee's company
    enrolled_at TIMESTAMPTZ DEFAULT NOW(),
    attended BOOLEAN DEFAULT FALSE,
    completion_date TIMESTAMPTZ,
    certificate_s3_key TEXT, -- Optional digital certificate
    feedback_rating SMALLINT, -- e.g., 1-5
    feedback_text TEXT,
    UNIQUE (training_session_id, employee_user_id)
);
ALTER TABLE training_enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_enrollment_for_employee ON training_enrollments FOR ALL
    USING (
        'EMPLOYEE' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        employee_user_id = current_setting('app.current_user_id', true)::uuid
    );
CREATE POLICY manage_enrollments_for_ohs_specialist_host ON training_enrollments FOR ALL
    USING (
        'OHS_SPECIALIST' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (SELECT 1 FROM training_sessions ts WHERE ts.id = training_enrollments.training_session_id AND ts.host_user_id = current_setting('app.current_user_id', true)::uuid)
    );
CREATE POLICY manage_enrollments_for_tenant_admin ON training_enrollments FOR ALL
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE training_quizzes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    created_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- RLS: Similar to training_sessions (OHS and TenantAdmin can manage for their tenant)
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
    quiz_id UUID NOT NULL REFERENCES training_quizzes(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized for RLS
    question_text TEXT NOT NULL,
    question_type TEXT NOT NULL, -- e.g., 'MULTIPLE_CHOICE', 'SINGLE_CHOICE', 'TEXT_INPUT'
    options JSONB, -- For multiple choice: [{ "id": "A", "text": "Option A"}, ...]
    correct_answer_key TEXT, -- For single/multiple choice, key of the correct option(s)
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
                ('OHS_SPECIALIST' = ANY(get_current_user_roles()) AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid) OR
                ('TENANT_ADMIN' = ANY(get_current_user_roles()))
            )
        )
    );
CREATE POLICY view_quiz_questions_for_tenant_members ON quiz_questions FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE quiz_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quiz_id UUID NOT NULL REFERENCES training_quizzes(id) ON DELETE CASCADE,
    enrollment_id UUID UNIQUE REFERENCES training_enrollments(id) ON DELETE CASCADE, -- Link to the specific enrollment
    employee_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized for RLS
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    score NUMERIC(5,2), -- e.g., 85.50
    passed BOOLEAN
);
-- RLS: Employee sees own. OHS/Admin see relevant attempts.
ALTER TABLE quiz_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_quiz_attempt ON quiz_attempts FOR ALL
    USING (employee_user_id = current_setting('app.current_user_id', true)::uuid AND 'EMPLOYEE' = ANY(get_current_user_roles()));
CREATE POLICY view_quiz_attempts_for_ohs_or_admin ON quiz_attempts FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('TENANT_ADMIN' = ANY(get_current_user_roles())) OR
            ('OHS_SPECIALIST' = ANY(get_current_user_roles()) AND EXISTS (
                SELECT 1 FROM training_quizzes tq
                WHERE tq.id = quiz_attempts.quiz_id AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid
            ))
        )
    );


CREATE TABLE quiz_attempt_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempt_id UUID NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
    question_id UUID NOT NULL REFERENCES quiz_questions(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE, -- Denormalized for RLS
    answer_key TEXT, -- e.g., "A" for multiple choice
    answer_text TEXT, -- For text input
    is_correct BOOLEAN,
    submitted_at TIMESTAMPTZ DEFAULT NOW()
);
-- RLS: Employee sees own. OHS/Admin see relevant answers.
ALTER TABLE quiz_attempt_answers ENABLE ROW LEVEL SECURITY;
CREATE POLICY view_own_quiz_attempt_answers ON quiz_attempt_answers FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM quiz_attempts qa
            WHERE qa.id = quiz_attempt_answers.attempt_id AND qa.employee_user_id = current_setting('app.current_user_id', true)::uuid AND 'EMPLOYEE' = ANY(get_current_user_roles())
        )
    );
CREATE POLICY view_quiz_attempt_answers_for_ohs_or_admin ON quiz_attempt_answers FOR SELECT
    USING (
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        (
            ('TENANT_ADMIN' = ANY(get_current_user_roles())) OR
            ('OHS_SPECIALIST' = ANY(get_current_user_roles()) AND EXISTS (
                SELECT 1 FROM quiz_attempts qa
                JOIN training_quizzes tq ON tq.id = qa.quiz_id
                WHERE qa.id = quiz_attempt_answers.attempt_id AND tq.created_by_user_id = current_setting('app.current_user_id', true)::uuid
            ))
        )
    );


-- 5. SAFETY REPORTING & FEEDBACK

CREATE TABLE safety_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    reporter_user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- NULL if anonymous
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    location_description TEXT,
    is_anonymous BOOLEAN DEFAULT FALSE,
    status safety_report_status NOT NULL DEFAULT 'OPEN',
    assigned_to_user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- OHS Specialist
    resolution_details TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE safety_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_own_safety_reports_for_employee ON safety_reports FOR ALL
    USING (
        NOT is_anonymous AND -- Cannot modify if anonymous after creation by self
        reporter_user_id = current_setting('app.current_user_id', true)::uuid AND
        'EMPLOYEE' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid
    );
-- Allow employee to create anonymous reports (INSERT only)
CREATE POLICY insert_safety_reports_for_employee ON safety_reports FOR INSERT
    WITH CHECK (
        'EMPLOYEE' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        company_id = current_setting('app.current_company_id', true)::uuid AND
        (is_anonymous OR reporter_user_id = current_setting('app.current_user_id', true)::uuid)
    );
CREATE POLICY manage_safety_reports_for_ohs_specialist ON safety_reports FOR ALL
    USING (
        'OHS_SPECIALIST' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM ohs_specialist_company_assignments osca
            WHERE osca.ohs_specialist_user_id = current_setting('app.current_user_id', true)::uuid AND osca.company_id = safety_reports.company_id
        )
    );
CREATE POLICY manage_safety_reports_for_tenant_admin ON safety_reports FOR ALL
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);


-- 6. RISK ANALYSIS

CREATE TABLE risk_analysis_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    creator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist
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
            ('OHS_SPECIALIST' = ANY(get_current_user_roles()) AND creator_user_id = current_setting('app.current_user_id', true)::uuid) OR
            ('TENANT_ADMIN' = ANY(get_current_user_roles()))
        )
    );
CREATE POLICY view_risk_templates_for_tenant_members ON risk_analysis_templates FOR SELECT
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);


CREATE TABLE risk_analysis_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES risk_analysis_templates(id) ON DELETE CASCADE,
    checker_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- OHS Specialist
    data_json JSONB NOT NULL, -- Filled-in template data
    status TEXT, -- e.g., 'DRAFT', 'SUBMITTED', 'REVIEWED'
    overall_risk_score NUMERIC(5,2),
    recommendations TEXT,
    checked_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE risk_analysis_checks ENABLE ROW LEVEL SECURITY;
CREATE POLICY manage_risk_checks_for_ohs_specialist ON risk_analysis_checks FOR ALL
    USING (
        'OHS_SPECIALIST' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        checker_user_id = current_setting('app.current_user_id', true)::uuid AND
        EXISTS (
            SELECT 1 FROM ohs_specialist_company_assignments osca
            WHERE osca.ohs_specialist_user_id = risk_analysis_checks.checker_user_id AND osca.company_id = risk_analysis_checks.company_id
        )
    );
CREATE POLICY manage_risk_checks_for_tenant_admin ON risk_analysis_checks FOR ALL
    USING ('TENANT_ADMIN' = ANY(get_current_user_roles()) AND tenant_id = current_setting('app.current_tenant_id', true)::uuid);
CREATE POLICY view_risk_checks_for_company_employee ON risk_analysis_checks FOR SELECT -- Employees might view completed checks for their company
    USING (
        'EMPLOYEE' = ANY(get_current_user_roles()) AND
        tenant_id = current_setting('app.current_tenant_id', true)::uuid AND
        company_id = current_setting('app.current_company_id', true)::uuid AND
        status = 'REVIEWED' -- Or some other 'published' status
    );


-- 7. NOTIFICATIONS

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


-- 8. COMMUNICATION LOGS (Simplified)

CREATE TABLE call_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
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


-- 9. SYSTEM SETTINGS (SuperAdmin or specific TenantAdmin managed)
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

-- Training Sessions table
CREATE INDEX idx_training_sessions_tenant_id ON training_sessions(tenant_id);
CREATE INDEX idx_training_sessions_host_user_id ON training_sessions(host_user_id);

-- Training Enrollments table
CREATE INDEX idx_training_enrollments_tenant_id ON training_enrollments(tenant_id);
CREATE INDEX idx_training_enrollments_session_id ON training_enrollments(training_session_id);
CREATE INDEX idx_training_enrollments_employee_user_id ON training_enrollments(employee_user_id);

-- Safety Reports table
CREATE INDEX idx_safety_reports_tenant_id ON safety_reports(tenant_id);
CREATE INDEX idx_safety_reports_company_id ON safety_reports(company_id);
CREATE INDEX idx_safety_reports_status ON safety_reports(status);
CREATE INDEX idx_safety_reports_assigned_to ON safety_reports(assigned_to_user_id);

-- Notifications
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);

-- Add more indexes as needed based on query patterns.


Explanation and Considerations:

users Table: Central user store. tenant_id and company_id here are for the primary association, especially for Employees. SuperAdmins will have tenant_id as NULL.

tenants Table: Defines the OHS firms.

user_context_roles Table: This is crucial for flexible role management. A user can be a TENANT_ADMIN for tenant_A and also an OHS_SPECIALIST for tenant_A. An Employee has an EMPLOYEE role linked to their tenant_id and company_id. SuperAdmins have a SUPER_ADMIN role with tenant_id and company_id as NULL.

The application backend, upon login, will query this table to populate app.current_user_roles, app.current_tenant_id, and app.current_company_id session variables.

companies Table: Client companies managed by a Tenant.

ohs_specialist_company_assignments & doctor_company_assignments: These tables explicitly link OHS Specialists and Doctors to the multiple companies they serve within their tenant. This is key for their RLS.

employee_profiles: Specific details for employees. tenant_id is added for RLS, derived from the employee's company.

RLS Policies:

USING clause: Defines which rows are visible for SELECT, UPDATE, DELETE.

WITH CHECK clause: Defines which rows can be INSERTed or UPDATEd.

Policies are generally structured to:

Allow SuperAdmins broad access.

Restrict TenantAdmins to their tenant_id.

Restrict OHS/Doctors to their tenant_id and further to companies they are assigned to.

Restrict Employees to their company_id (and thus tenant_id) and their own data.

tenant_id in many tables: This denormalization is essential for efficient RLS. While it can be derived through joins, having it directly on the table makes RLS policies simpler and often more performant.

get_current_user_roles() function: A helper to parse the comma-separated string from current_setting('app.current_user_roles', true) into a text array for easier use in policies (e.g., 'ROLE_NAME' = ANY(get_current_user_roles())).

"Admin also be OhsSpecialist": This is handled by the user_context_roles table. A user can have multiple role entries for the same tenant_id. The app.current_user_roles session variable will reflect all active roles for the current context.

Complexity: RLS policies can become complex. Thorough testing is critical. The provided policies are a starting point and might need refinement based on specific edge cases and access patterns.

Performance: While RLS is powerful, complex policies can impact performance. Ensure your queries are efficient and that tables are properly indexed, especially on tenant_id, company_id, and user_id columns used in RLS.

Application Logic: The backend (Axum) must correctly set the current_setting variables at the beginning of each database session/transaction for the logged-in user. If these are not set, RLS will likely deny all access.

This schema provides a solid foundation for your multi-tenant application with row-level security. Remember to iterate and refine as you develop the application and encounter specific access control scenarios.