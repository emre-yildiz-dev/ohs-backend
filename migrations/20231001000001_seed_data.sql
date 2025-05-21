--------------------------------------------------------------------------------
-- TENANTS AND COMPANIES
--------------------------------------------------------------------------------

-- Create a demo tenant
INSERT INTO tenants (id, name, is_active)
VALUES (
    '10000000-0000-0000-0000-000000000000',
    'OHS Demo Tenant',
    TRUE
);

-- Insert demo companies
INSERT INTO companies (id, tenant_id, name, status)
VALUES 
(
    '11111111-1111-1111-1111-111111111111',
    '10000000-0000-0000-0000-000000000000',
    'OHS Demo Company',
    'active'
),
(
    '11111111-1111-1111-1111-222222222222',
    '10000000-0000-0000-0000-000000000000',
    'Construction Corp',
    'active'
);

-- Add company profiles
INSERT INTO company_profiles (
    company_id, 
    contact_email,
    contact_phone,
    address,
    city,
    country
)
VALUES
(
    '11111111-1111-1111-1111-111111111111',
    'contact@ohsdemocompany.com',
    '+1-555-123-4567',
    '123 Safety Street',
    'Safetyville',
    'United States'
),
(
    '11111111-1111-1111-1111-222222222222',
    'contact@constructioncorp.com',
    '+1-555-987-6543',
    '456 Building Ave',
    'Constructville',
    'United States'
);

--------------------------------------------------------------------------------
-- USERS
--------------------------------------------------------------------------------

-- Insert an initial superadmin user
INSERT INTO users (
    id,
    email,
    password_hash,
    status
)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    'admin@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'active'
);

-- Insert tenant admin
INSERT INTO users (
    id,
    tenant_id,
    email,
    password_hash,
    status
)
VALUES (
    '11111111-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000000',
    'tenant-admin@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'active'
);

-- Insert a test OHS specialist
INSERT INTO users (
    id,
    tenant_id,
    email,
    password_hash,
    status,
    company_id
)
VALUES (
    '22222222-2222-2222-2222-222222222222',
    '10000000-0000-0000-0000-000000000000',
    'specialist@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'active',
    '11111111-1111-1111-1111-111111111111'
);

-- Insert a test doctor
INSERT INTO users (
    id,
    tenant_id,
    email,
    password_hash,
    status,
    company_id
)
VALUES (
    '33333333-3333-3333-3333-333333333333',
    '10000000-0000-0000-0000-000000000000',
    'doctor@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'active',
    '11111111-1111-1111-1111-111111111111'
);

-- Insert multiple test employees
INSERT INTO users (
    id,
    tenant_id,
    email,
    password_hash,
    status,
    company_id
)
VALUES 
(
    '44444444-4444-4444-4444-444444444444',
    '10000000-0000-0000-0000-000000000000',
    'employee1@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'active',
    '11111111-1111-1111-1111-111111111111'
),
(
    '44444444-4444-4444-4444-555555555555',
    '10000000-0000-0000-0000-000000000000',
    'employee2@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'active',
    '11111111-1111-1111-1111-111111111111'
),
(
    '44444444-4444-4444-4444-666666666666',
    '10000000-0000-0000-0000-000000000000',
    'employee3@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'active',
    '11111111-1111-1111-1111-222222222222'
);

--------------------------------------------------------------------------------
-- USER ROLES 
--------------------------------------------------------------------------------

-- Assign user tenant context roles
INSERT INTO user_tenant_context_roles (user_id, tenant_id, company_id, role)
VALUES
('00000000-0000-0000-0000-000000000000', NULL, NULL, 'super_admin'),
('11111111-0000-0000-0000-000000000000', '10000000-0000-0000-0000-000000000000', NULL, 'tenant_admin'),
('22222222-2222-2222-2222-222222222222', '10000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'ohs_specialist'),
('33333333-3333-3333-3333-333333333333', '10000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'doctor'),
('44444444-4444-4444-4444-444444444444', '10000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'employee'),
('44444444-4444-4444-4444-555555555555', '10000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'employee'),
('44444444-4444-4444-4444-666666666666', '10000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-222222222222', 'employee');

-- Assign company assignments for professionals
INSERT INTO ohs_specialist_company_assignments (ohs_specialist_user_id, company_id, tenant_id)
VALUES
('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000000'),
('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-222222222222', '10000000-0000-0000-0000-000000000000');

INSERT INTO doctor_company_assignments (doctor_user_id, company_id, tenant_id)
VALUES
('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '10000000-0000-0000-0000-000000000000');

--------------------------------------------------------------------------------
-- USER PROFILES
--------------------------------------------------------------------------------

INSERT INTO user_profiles (
    user_id, 
    first_name,
    last_name,
    phone_number, 
    date_of_birth, 
    profile_picture_url, 
    company_id,
    department,
    job_title
)
VALUES
(
    '00000000-0000-0000-0000-000000000000',
    'Super',
    'Admin',
    '+1-555-000-0000',
    '1980-01-01',
    'https://example.com/images/superadmin.jpg',
    NULL,
    NULL,
    'Super Administrator'
),
(
    '11111111-0000-0000-0000-000000000000',
    'Tenant',
    'Admin',
    '+1-555-111-1111',
    '1982-02-02',
    'https://example.com/images/tenantadmin.jpg',
    NULL,
    NULL,
    'Tenant Administrator'
),
(
    '22222222-2222-2222-2222-222222222222',
    'Safety',
    'Specialist',
    '+1-555-234-5678',
    '1985-06-15',
    'https://example.com/images/specialist.jpg',
    '11111111-1111-1111-1111-111111111111',
    'OHS Department',
    'Senior Safety Specialist'
),
(
    '33333333-3333-3333-3333-333333333333',
    'Medical',
    'Doctor',
    '+1-555-345-6789',
    '1980-03-22',
    'https://example.com/images/doctor.jpg',
    '11111111-1111-1111-1111-111111111111',
    'Medical Department',
    'Workplace Physician'
),
(
    '44444444-4444-4444-4444-444444444444',
    'John',
    'Smith',
    '+1-555-456-7890',
    '1990-11-08',
    'https://example.com/images/employee1.jpg',
    '11111111-1111-1111-1111-111111111111',
    'Engineering',
    'Software Developer'
),
(
    '44444444-4444-4444-4444-555555555555',
    'Jane',
    'Doe',
    '+1-555-567-8901',
    '1992-05-15',
    'https://example.com/images/employee2.jpg',
    '11111111-1111-1111-1111-111111111111',
    'Marketing',
    'Marketing Specialist'
),
(
    '44444444-4444-4444-4444-666666666666',
    'Alex',
    'Johnson',
    '+1-555-678-9012',
    '1988-09-22',
    'https://example.com/images/employee3.jpg',
    '11111111-1111-1111-1111-222222222222',
    'Operations',
    'Project Manager'
);

--------------------------------------------------------------------------------
-- SAFETY & RISK MANAGEMENT
--------------------------------------------------------------------------------

-- Create a risk analysis template
INSERT INTO risk_analysis_templates (
    id,
    tenant_id,
    name,
    description,
    creator_user_id,
    structure_json,
    created_at
)
VALUES
(
    '55555555-5555-5555-5555-555555555555',
    '10000000-0000-0000-0000-000000000000',
    'Office Safety Assessment',
    'Standard template for assessing office workplace safety',
    '22222222-2222-2222-2222-222222222222',
    '{
        "sections": [
            {
                "name": "Environmental Hazards",
                "questions": [
                    {
                        "id": "q1",
                        "text": "Are all walkways clear of obstacles?",
                        "type": "yes_no"
                    },
                    {
                        "id": "q2",
                        "text": "Are electrical cords and cables properly secured?",
                        "type": "yes_no"
                    }
                ]
            },
            {
                "name": "Fire Safety",
                "questions": [
                    {
                        "id": "q3",
                        "text": "Are fire extinguishers easily accessible?",
                        "type": "yes_no"
                    },
                    {
                        "id": "q4",
                        "text": "Are emergency exits clearly marked?",
                        "type": "yes_no"
                    }
                ]
            }
        ]
    }',
    NOW() - INTERVAL '30 days'
);

-- Create a risk analysis check instance
INSERT INTO risk_analysis_checks (
    id,
    tenant_id,
    company_id,
    template_id,
    checker_user_id,
    status,
    data_json,
    overall_risk_score,
    recommendations,
    checked_at
)
VALUES
(
    '66666666-6666-6666-6666-666666666666',
    '10000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    '55555555-5555-5555-5555-555555555555',
    '22222222-2222-2222-2222-222222222222',
    'completed',
    '{
        "answers": [
            {
                "id": "q1",
                "answer": "yes",
                "notes": "All walkways are clear"
            },
            {
                "id": "q2",
                "answer": "no",
                "notes": "Some cables in the meeting room need to be secured"
            },
            {
                "id": "q3",
                "answer": "yes",
                "notes": "Fire extinguishers are properly mounted"
            },
            {
                "id": "q4",
                "answer": "yes",
                "notes": "All exits have illuminated signs"
            }
        ]
    }',
    75.5,
    'Cable management in meeting room requires attention. Schedule maintenance within 2 weeks.',
    NOW() - INTERVAL '14 days'
);

-- Create a safety report
INSERT INTO safety_reports (
    id,
    tenant_id, 
    company_id,
    reporter_user_id,
    title,
    description,
    location_description,
    is_anonymous,
    priority,
    status,
    assigned_to_user_id,
    created_at
)
VALUES
(
    '77777777-7777-7777-7777-777777777777',
    '10000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    '44444444-4444-4444-4444-444444444444',
    'Faulty Electrical Outlet',
    'Electrical outlet in the break room is sparking when used',
    'Break Room - North Wall',
    FALSE,
    'high',
    'in_review',
    '22222222-2222-2222-2222-222222222222',
    NOW() - INTERVAL '5 days'
);

--------------------------------------------------------------------------------
-- APPOINTMENTS
--------------------------------------------------------------------------------

-- Create professional availability
INSERT INTO professional_availabilities (
    id,
    tenant_id,
    professional_user_id,
    start_time,
    end_time
)
VALUES
(
    '88888888-8888-8888-8888-888888888888',
    '10000000-0000-0000-0000-000000000000',
    '33333333-3333-3333-3333-333333333333',
    NOW() + INTERVAL '1 day' + INTERVAL '9 hours',
    NOW() + INTERVAL '1 day' + INTERVAL '17 hours'
);

-- Create an appointment
INSERT INTO appointments (
    id,
    tenant_id,
    company_id,
    employee_user_id,
    professional_user_id,
    appointment_type,
    start_time,
    end_time,
    status,
    reason_for_visit,
    created_at
)
VALUES
(
    '99999999-9999-9999-9999-999999999999',
    '10000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    '44444444-4444-4444-4444-444444444444',
    '33333333-3333-3333-3333-333333333333',
    'medical_checkup',
    NOW() + INTERVAL '2 days' + INTERVAL '10 hours',
    NOW() + INTERVAL '2 days' + INTERVAL '11 hours',
    'confirmed',
    'Annual medical checkup',
    NOW() - INTERVAL '3 days'
);

--------------------------------------------------------------------------------
-- TRAINING MODULE
--------------------------------------------------------------------------------

-- Create a training session
INSERT INTO training_sessions (
    id,
    tenant_id,
    title,
    description,
    host_user_id,
    training_type,
    start_time,
    end_time,
    max_participants,
    status,
    created_at
)
VALUES
(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '10000000-0000-0000-0000-000000000000',
    'Workplace Safety Fundamentals',
    'Essential safety training for all employees',
    '22222222-2222-2222-2222-222222222222',
    'live_webinar',
    NOW() + INTERVAL '7 days' + INTERVAL '13 hours',
    NOW() + INTERVAL '7 days' + INTERVAL '15 hours',
    30,
    'scheduled',
    NOW() - INTERVAL '10 days'
);

-- Create training enrollment
INSERT INTO training_enrollments (
    id,
    tenant_id,
    employee_user_id,
    training_session_id,
    company_id,
    status,
    enrolled_at
)
VALUES
(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    '10000000-0000-0000-0000-000000000000',
    '44444444-4444-4444-4444-444444444444',
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'registered',
    NOW() - INTERVAL '8 days'
);

--------------------------------------------------------------------------------
-- NOTIFICATIONS
--------------------------------------------------------------------------------

-- Create notifications
INSERT INTO notifications (
    id,
    user_id,
    tenant_id,
    notification_type,
    title,
    message,
    related_entity_id,
    related_entity_type,
    is_read,
    created_at
)
VALUES
(
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    '44444444-4444-4444-4444-444444444444',
    '10000000-0000-0000-0000-000000000000',
    'appointment_reminder',
    'Upcoming Appointment',
    'You have a medical checkup appointment tomorrow at 10:00 AM',
    '99999999-9999-9999-9999-999999999999',
    'APPOINTMENT',
    FALSE,
    NOW() - INTERVAL '1 day'
),
(
    'cccccccc-cccc-cccc-cccc-dddddddddddd',
    '22222222-2222-2222-2222-222222222222',
    '10000000-0000-0000-0000-000000000000',
    'safety_report_update',
    'Safety Report Assigned',
    'A new high-priority safety report has been assigned to you',
    '77777777-7777-7777-7777-777777777777',
    'SAFETY_REPORT',
    TRUE,
    NOW() - INTERVAL '5 days'
);

--------------------------------------------------------------------------------
-- SYSTEM SETTINGS
--------------------------------------------------------------------------------

-- Create system settings
INSERT INTO system_settings (
    id,
    tenant_id,
    setting_key,
    setting_value,
    description
)
VALUES
(
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    NULL,
    'DEFAULT_NOTIFICATION_SETTINGS',
    '{"email": true, "push": true, "sms": false}',
    'Default notification preferences for new users'
),
(
    'dddddddd-dddd-dddd-dddd-eeeeeeeeeeee',
    '10000000-0000-0000-0000-000000000000',
    'TENANT_BRANDING',
    '{"primaryColor": "#1E88E5", "logoUrl": "https://example.com/tenant-logo.png"}',
    'Branding configuration for tenant'
);