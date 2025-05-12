use axum::extract::ws::{Message, WebSocketUpgrade};
use axum::extract::State;
use axum::response::IntoResponse;
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;
use futures_util::{StreamExt, SinkExt};

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<Arc<Mutex<broadcast::Sender<String>>>>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(socket, state))
}

async fn handle_socket(
    socket: axum::extract::ws::WebSocket,
    state: Arc<Mutex<broadcast::Sender<String>>>,
) {
    // Split the socket into sender and receiver
    let (mut sender, mut receiver) = socket.split();
    
    let tx = state.lock().unwrap().clone();
    let mut rx = tx.subscribe();

    // Task for receiving messages from the WebSocket and forwarding to broadcast
    let tx_clone = tx.clone();
    let recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            if let Message::Text(text) = msg {
                let _ = tx_clone.send(text.to_string());
            }
        }
    });

    // Task for forwarding messages from broadcast to the WebSocket
    let send_task = tokio::spawn(async move {
        while let Ok(msg) = rx.recv().await {
            if sender.send(Message::Text(msg.into())).await.is_err() {
                break;
            }
        }
    });

    // Wait for either task to finish
    tokio::select! {
        _ = recv_task => {},
        _ = send_task => {},
    }
}
