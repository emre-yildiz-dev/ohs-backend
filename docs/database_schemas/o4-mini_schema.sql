-- 1) Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2) Tenants
CREATE TABLE tenants (
  id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name      TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3) Users
CREATE TABLE users (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id  UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  email      TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role       TEXT NOT NULL CHECK (role IN ('super_admin','admin','specialist','doctor','employee')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- super_admin can do anything
CREATE POLICY users_super_admin ON users
  FOR ALL
  USING ( current_setting('app.current_role', true) = 'super_admin' );

-- within-tenant read for everyone else
CREATE POLICY users_select_tenant ON users
  FOR SELECT
  USING (
    current_setting('app.current_role', true) <> 'super_admin'
    AND tenant_id = (current_setting('app.current_tenant')::UUID)
  );

-- users can update their own row
CREATE POLICY users_update_self ON users
  FOR UPDATE
  USING (
    current_setting('app.current_role', true) = 'admin'
    AND tenant_id = (current_setting('app.current_tenant')::UUID)
  ) WITH CHECK (
    tenant_id = (current_setting('app.current_tenant')::UUID)
  );

-- Admins can insert new users in their tenant
CREATE POLICY users_insert_admin ON users
  FOR INSERT
  WITH CHECK (
    (current_setting('app.current_role', true) = 'admin'
     AND tenant_id = (current_setting('app.current_tenant')::UUID))
    OR current_setting('app.current_role', true) = 'super_admin'
  );

-- 4) Appointments
CREATE TABLE appointments (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id UUID NOT NULL REFERENCES users(id),
  specialist_id UUID REFERENCES users(id),
  doctor_id   UUID REFERENCES users(id),
  start_time  TIMESTAMPTZ NOT NULL,
  end_time    TIMESTAMPTZ NOT NULL,
  status      TEXT NOT NULL CHECK (status IN ('booked','cancelled','completed')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;

-- super_admin can do anything
CREATE POLICY appt_super_admin ON appointments
  FOR ALL
  USING ( current_setting('app.current_role', true) = 'super_admin' );

-- tenant-scoped access: everyone in the same tenant can see
CREATE POLICY appt_tenant_read ON appointments
  FOR SELECT
  USING (
    current_setting('app.current_role', true) <> 'super_admin'
    AND tenant_id = (current_setting('app.current_tenant')::UUID)
  );

-- employee can insert only their own tenant
CREATE POLICY appt_insert ON appointments
  FOR INSERT
  WITH CHECK (
    tenant_id = (current_setting('app.current_tenant')::UUID)
  );

-- admin/specialist/doctor can update status
CREATE POLICY appt_update_status ON appointments
  FOR UPDATE
  USING (
    current_setting('app.current_role', true) IN ('admin','specialist','doctor')
    AND tenant_id = (current_setting('app.current_tenant')::UUID)
  ) WITH CHECK (
    status IN ('booked','cancelled','completed')
    AND tenant_id = (current_setting('app.current_tenant')::UUID)
  );

-- 5) Safety Reports
CREATE TABLE safety_reports (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  reporter_id UUID NOT NULL REFERENCES users(id),
  anonymous   BOOLEAN NOT NULL DEFAULT FALSE,
  content     TEXT NOT NULL,
  status      TEXT NOT NULL CHECK(status IN ('open','in_review','resolved')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE safety_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY rpt_super_admin ON safety_reports
  FOR ALL
  USING ( current_setting('app.current_role', true) = 'super_admin' );

CREATE POLICY rpt_tenant_read ON safety_reports
  FOR SELECT
  USING (
    current_setting('app.current_role', true) <> 'super_admin'
    AND tenant_id = (current_setting('app.current_tenant')::UUID)
  );

-- reporters can insert
CREATE POLICY rpt_insert ON safety_reports
  FOR INSERT
  WITH CHECK (
    tenant_id = (current_setting('app.current_tenant')::UUID)
  );

-- staff can update status
CREATE POLICY rpt_update_status ON safety_reports
  FOR UPDATE
  USING (
    current_setting('app.current_role', true) IN ('admin','specialist','doctor')
    AND tenant_id = (current_setting('app.current_tenant')::UUID)
  ) WITH CHECK (
    status IN ('open','in_review','resolved')
    AND tenant_id = (current_setting('app.current_tenant')::UUID)
  );