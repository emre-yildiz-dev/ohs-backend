use axum::{response::IntoResponse, response::Html, response::Response, http::StatusCode};
use askama::Template;
use tracing::error;

#[derive(Template)]
#[template(path = "admin/dashboard.html")]
struct DashboardTemplate;

struct HtmlTemplate<T>(T);

impl<T> IntoResponse for HtmlTemplate<T>
where
    T: Template,
{
    fn into_response(self) -> Response {
        match self.0.render() {
            Ok(html) => Html(html).into_response(),
            Err(e) => {
                error!("Failed to render template: {}", e);
                (StatusCode::INTERNAL_SERVER_ERROR, "Internal Server Error").into_response()
            }
        }
    }
}

pub async fn admin_dashboard() -> impl IntoResponse {
    HtmlTemplate(DashboardTemplate)
}

#[derive(Template)]
#[template(path = "public/login.html")]
struct LoginTemplate;

pub async fn admin_login() -> impl IntoResponse {
    HtmlTemplate(LoginTemplate)
}

