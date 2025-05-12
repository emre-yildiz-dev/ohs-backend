# Occupational Health and Safety Specialist Backend Application

## Requirements

### 1. Overview

This multi-tenant backend application is designed to facilitate communication between Occupational Health and Safety Specialists (OhsSpecialist), Workplace Doctor(Doctor), and Employees. This app will enable employees to engage in real-time audio/video calls with safety experts, attend safety rainnigs, and schedule appointments online.

### 2. User Roles

#### 2.1 Employee

- Login to the application.
- View OhsSpecialist profiles.
- View Workplace Doctor profiles.
- Initiate or receive video/audio calls in the appointment time.
- Book an appointment with an OhsSpecialist.
- Book an appointment with a Workplace Doctor.
- Attend safety training sessions.
- View past appointment and training history.
- Receive notifications and reminders.
- Submit safety-related questions or reports.

#### 2.2 Occupational Health and Safety Specialist (OhsSpecialist)

- Login to the application
- Manage Employees, and Doctors for related companies.
- Manage availability for appointments.
- Accept or decline appointment requests.
- Initiate or receive video/audio calls.
- Upload and manage training materials (video, PDF, slides).
- Host live training sessions.
- Answer employee questions or respond to reports.
- View communication and appointment logs.
- Receive notifications about requests or reports.

#### 2.3 Workplace Doctor (Doctor)

- Login to the application.
- Manage avaiability for appointments.
- Accept or decline appointment requests.
- Initiate or receive video/audio calls.
- Answer employee questions.
- Receive notifications about requests.

#### 2.4 Admin

- Login to the application.
- Manage companies (Multi-tenant).
- Approve OhsSpecialist and doctor accounts.
- Manage OhsSpecialist, Doctor, Employee registrations and roles in the application.
- View system analytics.
- Manage content and app settings.

#### SuperAdmin

- Approve admin accounts.
- Manage admin constraints like rights to manage company counts, user counts etc.
- View all system resources and analytics.

### 3. Core Features

#### 3.1 Authentication & Profile Management

- Email based login.
- Password reset and account recovery.
- Profile setup with name, department, job title, etc.
- Role management (Admin)

#### 3.2 Real-time Communication

- In-app video and audio calling functionality.
- Call scheduling and reminders.
- Call duration tracking.
- End-to-end encryption for privacy.

#### 3.3 Training Module

- Live training events via streaming.
- Completion tracking and digital certificates.
- Quizes after sessions to measure understanding.
- Feedback submission for traning sessions.

#### 3.4 Appointment System

- Calendar view for availability.
- Appointment booking and cancellation.
- Automatic time zone adjustment (for remote work scenarios).
- Notifications (email, push) for confirmed or cancelled appointments.
- Waitlist or reschedule feature if a time slot is full.

#### 3.5 Safety Reporting & Feedback

- Employees can submit safety concerns/issues anonymously or with identity.
- OhsSpecialist can respond, escalate, or archive the report.
- Status tracking(Open, In Review, Resolved).

#### 3.6 Push Notifications

- Training reminders.
- Upcoming appointment alerts.
- Important safety alerts or announcements.

#### 3.7 Multimedia Support

- Upload and display of PDFs, images.

### 4. Non-functional Requirements

- Platform: This backend app will serve React Native Expo IOS & Android client apps.
- Scalability: Should support 10,000+ concurrent users.
- Performance: Low-latency communication and fast media streaming.
- Availability: 99.9% uptime with fallback servers.

### 5. Technology Stack

- Frontend: Admin Console via HTMX, Askama, TailwindCss
- Backend: Rust Axum
- Database: Postgresql with sqlx
- Cache: Redis
- Message Broker: Redis Streams, Pub/Sub or Redis Lists/Sorted Sets
- Real-Time Communication: Mediasoup Rust crate
- Websocket Signaling: Axum websocket
- STUN/TURN Server: Coturn
- Authentication: JWT, RBAC
- Notification: Expo Push Notification, External Email Service
- Storage: Garage S3 with aws rust client
