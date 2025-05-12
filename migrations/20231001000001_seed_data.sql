-- Insert a test company
INSERT INTO companies (id, name, status, address, city, country)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'OHS Demo Company',
    'active',
    '123 Safety Street',
    'Safetyville',
    'United States'
);

-- Insert an initial superadmin user
-- Password hash for 'SuperAdmin123!' using argon2
INSERT INTO users (
    id,
    email,
    password_hash,
    first_name,
    last_name,
    role,
    status
)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    'admin@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'Super',
    'Admin',
    'super_admin',
    'active'
);

-- Insert a test OHS specialist
INSERT INTO users (
    id,
    email,
    password_hash,
    first_name,
    last_name,
    role,
    status,
    company_id,
    job_title
)
VALUES (
    '22222222-2222-2222-2222-222222222222',
    'specialist@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'Safety',
    'Specialist',
    'ohs_specialist',
    'active',
    '11111111-1111-1111-1111-111111111111',
    'Senior Safety Specialist'
);

-- Insert a test doctor
INSERT INTO users (
    id,
    email,
    password_hash,
    first_name,
    last_name,
    role,
    status,
    company_id,
    job_title
)
VALUES (
    '33333333-3333-3333-3333-333333333333',
    'doctor@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'Medical',
    'Doctor',
    'doctor',
    'active',
    '11111111-1111-1111-1111-111111111111',
    'Workplace Physician'
);

-- Insert a test employee
INSERT INTO users (
    id,
    email,
    password_hash,
    first_name,
    last_name,
    role,
    status,
    company_id,
    department,
    job_title
)
VALUES (
    '44444444-4444-4444-4444-444444444444',
    'employee@ohsapp.com',
    '$argon2id$v=19$m=16,t=2,p=1$wMWLJuQZCKZoVBuTKl3OZw$7YnZ1FXn/37Pr6uyC0xyAA', -- Password: SuperAdmin123!
    'Test',
    'Employee',
    'employee',
    'active',
    '11111111-1111-1111-1111-111111111111',
    'Engineering',
    'Software Developer'
); 