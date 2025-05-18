-- Enable Row Level Security
ALTER DATABASE ohs_app SET row_security = on;

-- Create necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create application-wide role for RLS
CREATE ROLE app_user;
CREATE ROLE super_admin;
CREATE ROLE tenant_admin;
CREATE ROLE ohs_specialist;
CREATE ROLE doctor;
CREATE ROLE employee;

-- =====================================================================
-- TENANT AND USER MANAGEMENT TABLES
-- =====================================================================

-- Tenant table to store information about OHS expert firms
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'active', -- active, suspended, inactive
    max_companies INT NOT NULL DEFAULT 5,
    max_users INT NOT NULL DEFAULT 100,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Companies table to store information about client companies
CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    address TEXT,
    phone VARCHAR(50),
    email VARCHAR(255),
    status VARCHAR(50) NOT NULL DEFAULT 'active', -- active, suspended, inactive
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create User table for all user types
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone VARCHAR(50),
    status VARCHAR(50) NOT NULL DEFAULT 'active', -- active, suspended, inactive
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMPTZ
);

-- Table to store user roles
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) NOT NULL UNIQUE CHECK (name IN ('super_admin', 'tenant_admin', 'ohs_specialist', 'doctor', 'employee'))
);

-- Insert predefined roles
INSERT INTO roles (name) VALUES 
    ('super_admin'), 
    ('tenant_admin'), 
    ('ohs_specialist'), 
    ('doctor'), 
    ('employee');

-- User-Role-Tenant relationship table
CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- Super admins don't need tenant_id
    CONSTRAINT valid_role_tenant CHECK (
        (role_id = (SELECT id FROM roles WHERE name = 'super_admin') AND tenant_id IS NULL) OR
        (role_id != (SELECT id FROM roles WHERE name = 'super_admin') AND tenant_id IS NOT NULL)
    ),
    UNIQUE(user_id, role_id, tenant_id)
);

-- User-Company relationship table
CREATE TABLE user_companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_role_id UUID NOT NULL REFERENCES user_roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, company_id, user_role_id)
);

-- Employee additional profile information
CREATE TABLE employee_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department VARCHAR(255),
    position VARCHAR(255),
    employee_id VARCHAR(100),
    date_of_birth DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, company_id)
);

-- Specialist profile information
CREATE TABLE specialist_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    specialty VARCHAR(255),
    certification VARCHAR(255),
    bio TEXT,
    profile_image_url VARCHAR(512),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, tenant_id)
);

-- Doctor profile information
CREATE TABLE doctor_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    specialty VARCHAR(255),
    certification VARCHAR(255),
    license_number VARCHAR(100),
    bio TEXT,
    profile_image_url VARCHAR(512),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, tenant_id)
);

-- =====================================================================
-- APPOINTMENT MANAGEMENT
-- =====================================================================

-- Table for availability slots
CREATE TABLE availability_slots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE, -- Can be NULL for general availability
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'available', -- available, booked, blocked
    recurring BOOLEAN NOT NULL DEFAULT FALSE,
    recurring_pattern VARCHAR(50), -- daily, weekly, monthly, etc.
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_time_range CHECK (end_time > start_time)
);

-- Table for appointments
CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- specialist or doctor
    availability_slot_id UUID NOT NULL REFERENCES availability_slots(id) ON DELETE CASCADE,
    appointment_type VARCHAR(50) NOT NULL, -- video, audio, in-person
    status VARCHAR(50) NOT NULL DEFAULT 'scheduled', -- scheduled, in-progress, completed, cancelled
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_appointment_time CHECK (end_time > start_time)
);

-- Table for appointment feedback
CREATE TABLE appointment_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    appointment_id UUID NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    comments TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================================
-- TRAINING MODULE
-- =====================================================================

-- Table for training sessions
CREATE TABLE training_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID REFERENCES companies(id) ON DELETE SET NULL, -- Can be NULL for general sessions
    title VARCHAR(255) NOT NULL,
    description TEXT,
    trainer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_type VARCHAR(50) NOT NULL, -- live, recorded
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'scheduled', -- scheduled, in-progress, completed, cancelled
    max_participants INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_session_time CHECK (end_time > start_time)
);

-- Table for training materials
CREATE TABLE training_materials (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    file_type VARCHAR(50) NOT NULL, -- pdf, video, slides
    file_url VARCHAR(512) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for training participation
CREATE TABLE training_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) NOT NULL DEFAULT 'registered', -- registered, attended, completed, no-show
    join_time TIMESTAMPTZ,
    leave_time TIMESTAMPTZ,
    certificate_issued BOOLEAN DEFAULT FALSE,
    certificate_url VARCHAR(512),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(training_session_id, employee_id)
);

-- Table for training quizzes
CREATE TABLE training_quizzes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    passing_score INTEGER NOT NULL DEFAULT 70,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for quiz questions
CREATE TABLE quiz_questions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    training_quiz_id UUID NOT NULL REFERENCES training_quizzes(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    question_type VARCHAR(50) NOT NULL, -- multiple-choice, true-false, short-answer
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for question options (for multiple choice)
CREATE TABLE question_options (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quiz_question_id UUID NOT NULL REFERENCES quiz_questions(id) ON DELETE CASCADE,
    option_text TEXT NOT NULL,
    is_correct BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for quiz attempts
CREATE TABLE quiz_attempts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    training_quiz_id UUID NOT NULL REFERENCES training_quizzes(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    score INTEGER,
    passed BOOLEAN,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for quiz answers
CREATE TABLE quiz_answers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quiz_attempt_id UUID NOT NULL REFERENCES quiz_attempts(id) ON DELETE CASCADE,
    quiz_question_id UUID NOT NULL REFERENCES quiz_questions(id) ON DELETE CASCADE,
    question_option_id UUID REFERENCES question_options(id) ON DELETE CASCADE,
    text_answer TEXT, -- For short-answer questions
    is_correct BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for training feedback
CREATE TABLE training_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    training_session_id UUID NOT NULL REFERENCES training_sessions(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    comments TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(training_session_id, employee_id)
);

-- =====================================================================
-- SAFETY REPORTING & FEEDBACK
-- =====================================================================

-- Table for safety reports
CREATE TABLE safety_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    employee_id UUID REFERENCES users(id) ON DELETE SET NULL, -- Can be NULL for anonymous reports
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    location VARCHAR(255),
    severity VARCHAR(50) NOT NULL, -- low, medium, high, critical
    status VARCHAR(50) NOT NULL DEFAULT 'open', -- open, in-review, resolved, archived
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for safety report responses
CREATE TABLE safety_report_responses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    safety_report_id UUID NOT NULL REFERENCES safety_reports(id) ON DELETE CASCADE,
    responder_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    response TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for safety report attachments
CREATE TABLE safety_report_attachments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    safety_report_id UUID NOT NULL REFERENCES safety_reports(id) ON DELETE CASCADE,
    file_type VARCHAR(50) NOT NULL, -- image, pdf, video
    file_url VARCHAR(512) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================================
-- RISK ANALYSIS
-- =====================================================================

-- Table for risk analysis templates
CREATE TABLE risk_analysis_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for risk analysis template items
CREATE TABLE risk_analysis_template_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    template_id UUID NOT NULL REFERENCES risk_analysis_templates(id) ON DELETE CASCADE,
    category VARCHAR(255) NOT NULL,
    question TEXT NOT NULL,
    recommendation TEXT,
    severity VARCHAR(50) NOT NULL, -- low, medium, high, critical
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for risk analysis assessments
CREATE TABLE risk_analysis_assessments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    template_id UUID NOT NULL REFERENCES risk_analysis_templates(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    conducted_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assessment_date DATE NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'in-progress', -- in-progress, completed, archived
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for risk analysis assessment results
CREATE TABLE risk_analysis_results (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    assessment_id UUID NOT NULL REFERENCES risk_analysis_assessments(id) ON DELETE CASCADE,
    template_item_id UUID NOT NULL REFERENCES risk_analysis_template_items(id) ON DELETE CASCADE,
    compliance_status VARCHAR(50) NOT NULL, -- compliant, non-compliant, not-applicable
    notes TEXT,
    action_required BOOLEAN DEFAULT FALSE,
    action_description TEXT,
    due_date DATE,
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================================
-- COMMUNICATION MODULE
-- =====================================================================

-- Table for communication sessions (audio/video calls)
CREATE TABLE communication_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    appointment_id UUID REFERENCES appointments(id) ON DELETE SET NULL,
    training_session_id UUID REFERENCES training_sessions(id) ON DELETE SET NULL,
    session_type VARCHAR(50) NOT NULL, -- audio, video, screen-share
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    status VARCHAR(50) NOT NULL DEFAULT 'scheduled', -- scheduled, in-progress, completed, failed
    media_server_id VARCHAR(255),
    recording_url VARCHAR(512),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT session_reference CHECK (
        (appointment_id IS NOT NULL AND training_session_id IS NULL) OR
        (appointment_id IS NULL AND training_session_id IS NOT NULL)
    )
);

-- Table for communication session participants
CREATE TABLE communication_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    communication_session_id UUID NOT NULL REFERENCES communication_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    join_time TIMESTAMPTZ,
    leave_time TIMESTAMPTZ,
    role VARCHAR(50) NOT NULL, -- host, participant
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for live chat messages during communication sessions
CREATE TABLE session_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    communication_session_id UUID NOT NULL REFERENCES communication_sessions(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================================
-- NOTIFICATION SYSTEM
-- =====================================================================

-- Table for notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    notification_type VARCHAR(50) NOT NULL, -- appointment, training, safety, system
    related_id UUID, -- Could be appointment_id, training_session_id, etc.
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for notification settings
CREATE TABLE notification_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notification_type VARCHAR(50) NOT NULL, -- appointment, training, safety, system
    email_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    push_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, notification_type)
);

-- Table for push notification tokens
CREATE TABLE push_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) NOT NULL,
    token TEXT NOT NULL,
    platform VARCHAR(50) NOT NULL, -- ios, android
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, device_id)
);

-- =====================================================================
-- AUTHENTICATION AND SESSION MANAGEMENT
-- =====================================================================

-- Table for refresh tokens
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Table for password reset tokens
CREATE TABLE password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================================
-- SYSTEM LOGS AND ANALYTICS
-- =====================================================================

-- Table for system audit logs
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    tenant_id UUID REFERENCES tenants(id) ON DELETE SET NULL,
    action VARCHAR(255) NOT NULL,
    entity_type VARCHAR(50) NOT NULL, -- user, tenant, company, etc.
    entity_id UUID,
    details JSONB,
    ip_address VARCHAR(50),
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================================
-- ROW LEVEL SECURITY POLICIES
-- =====================================================================

-- Create a session variable to store the current user's ID
CREATE OR REPLACE FUNCTION set_current_user_id(user_id UUID)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_user_id', user_id::TEXT, FALSE);
END;
$$ LANGUAGE plpgsql;

-- Create a session variable to store the current user's tenant ID
CREATE OR REPLACE FUNCTION set_current_tenant_id(tenant_id UUID)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_tenant_id', tenant_id::TEXT, FALSE);
END;
$$ LANGUAGE plpgsql;

-- Create a session variable to store the current user's role
CREATE OR REPLACE FUNCTION set_current_user_role(role_name TEXT)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_user_role', role_name, FALSE);
END;
$$ LANGUAGE plpgsql;

-- Enable RLS on the tenants table
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;

-- Super admins can see and manage all tenants
CREATE POLICY super_admin_tenants_policy ON tenants
    USING (current_setting('app.current_user_role') = 'super_admin');

-- Tenant admin, OHS specialists, and doctors can only see their own tenant
CREATE POLICY tenant_users_tenants_policy ON tenants
    USING (id = current_setting('app.current_tenant_id')::UUID AND 
           current_setting('app.current_user_role') IN ('tenant_admin', 'ohs_specialist', 'doctor'));

-- Enable RLS on companies table
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Super admins can see all companies
CREATE POLICY super_admin_companies_policy ON companies
    USING (current_setting('app.current_user_role') = 'super_admin');

-- Tenant admins, OHS specialists, and doctors can only see companies in their tenant
CREATE POLICY tenant_users_companies_policy ON companies
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID AND 
           current_setting('app.current_user_role') IN ('tenant_admin', 'ohs_specialist', 'doctor'));

-- Employees can only see their own company
CREATE POLICY employee_companies_policy ON companies
    USING (id IN (
        SELECT company_id FROM user_companies 
        WHERE user_id = current_setting('app.current_user_id')::UUID
    ) AND current_setting('app.current_user_role') = 'employee');

-- Enable RLS on users table
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Super admins can see all users
CREATE POLICY super_admin_users_policy ON users
    USING (current_setting('app.current_user_role') = 'super_admin');

-- Tenant admins can see users in their tenant
CREATE POLICY tenant_admin_users_policy ON users
    USING (id IN (
        SELECT user_id FROM user_roles 
        WHERE tenant_id = current_setting('app.current_tenant_id')::UUID
    ) AND current_setting('app.current_user_role') = 'tenant_admin');

-- OHS specialists and doctors can see users in companies they're assigned to
CREATE POLICY provider_users_policy ON users
    USING (id IN (
        SELECT uc.user_id FROM user_companies uc
        JOIN user_companies provider_uc ON provider_uc.company_id = uc.company_id
        WHERE provider_uc.user_id = current_setting('app.current_user_id')::UUID
    ) AND current_setting('app.current_user_role') IN ('ohs_specialist', 'doctor'));

-- Employees can see specialists, doctors, and other employees in their company
CREATE POLICY employee_users_policy ON users
    USING (id IN (
        SELECT uc.user_id FROM user_companies uc
        JOIN user_companies employee_uc ON employee_uc.company_id = uc.company_id
        WHERE employee_uc.user_id = current_setting('app.current_user_id')::UUID
    ) AND current_setting('app.current_user_role') = 'employee');

-- Users can always see themselves
CREATE POLICY self_users_policy ON users
    USING (id = current_setting('app.current_user_id')::UUID);

-- Apply RLS to other tables in a similar pattern
-- For example, for appointments:
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;

-- Super admins see all appointments
CREATE POLICY super_admin_appointments_policy ON appointments
    USING (current_setting('app.current_user_role') = 'super_admin');

-- Tenant admins see appointments in their tenant
CREATE POLICY tenant_admin_appointments_policy ON appointments
    USING (tenant_id = current_setting('app.current_tenant_id')::UUID AND 
           current_setting('app.current_user_role') = 'tenant_admin');

-- Providers (OHS specialists and doctors) see their own appointments
CREATE POLICY provider_appointments_policy ON appointments
    USING (provider_id = current_setting('app.current_user_id')::UUID AND 
           current_setting('app.current_user_role') IN ('ohs_specialist', 'doctor'));

-- Employees see their own appointments
CREATE POLICY employee_appointments_policy ON appointments
    USING (employee_id = current_setting('app.current_user_id')::UUID AND 
           current_setting('app.current_user_role') = 'employee');

-- Continue with similar policies for all tables that need RLS
-- Apply these principles to all tables containing sensitive data

-- =====================================================================
-- INDEXES FOR PERFORMANCE
-- =====================================================================

-- Create indexes on frequently queried columns

-- User related indexes
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_user_roles_user_id ON user_roles(user_id);
CREATE INDEX idx_user_roles_tenant_id ON user_roles(tenant_id);
CREATE INDEX idx_user_companies_user_id ON user_companies(user_id);
CREATE INDEX idx_user_companies_company_id ON user_companies(company_id);

-- Company related indexes
CREATE INDEX idx_companies_tenant_id ON companies(tenant_id);

-- Appointment related indexes
CREATE INDEX idx_appointments_tenant_id ON appointments(tenant_id);
CREATE INDEX idx_appointments_company_id ON appointments(company_id);
CREATE INDEX idx_appointments_employee_id ON appointments(employee_id);
CREATE INDEX idx_appointments_provider_id ON appointments(provider_id);
CREATE INDEX idx_appointments_start_time ON appointments(start_time);
CREATE INDEX idx_appointments_status ON appointments(status);

-- Training related indexes
CREATE INDEX idx_training_sessions_tenant_id ON training_sessions(tenant_id);
CREATE INDEX idx_training_sessions_company_id ON training_sessions(company_id);
CREATE INDEX idx_training_sessions_trainer_id ON training_sessions(trainer_id);
CREATE INDEX idx_training_sessions_start_time ON training_sessions(start_time);
CREATE INDEX idx_training_participants_training_session_id ON training_participants(training_session_id);
CREATE INDEX idx_training_participants_employee_id ON training_participants(employee_id);

-- Safety report related indexes
CREATE INDEX idx_safety_reports_tenant_id ON safety_reports(tenant_id);
CREATE INDEX idx_safety_reports_company_id ON safety_reports(company_id);
CREATE INDEX idx_safety_reports_employee_id ON safety_reports(employee_id);
CREATE INDEX idx_safety_reports_status ON safety_reports(status);

-- Risk analysis related indexes
CREATE INDEX idx_risk_analysis_assessments_tenant_id ON risk_analysis_assessments(tenant_id);
CREATE INDEX idx_risk_analysis_assessments_company_id ON risk_analysis_assessments(company_id);
CREATE INDEX idx_risk_analysis_assessments_conducted_by ON risk_analysis_assessments(conducted_by);

-- Communication related indexes
CREATE INDEX idx_communication_sessions_appointment_id ON communication_sessions(appointment_id);
CREATE INDEX idx_communication_sessions_training_session_id ON communication_sessions(training_session_id);
CREATE INDEX idx_communication_participants_communication_session_id ON communication_participants(communication_session_id);
CREATE INDEX idx_communication_participants_user_id ON communication_participants(user_id);

-- Notification related indexes
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_notifications_created_at ON notifications(created_at);

-- Authentication related indexes
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);