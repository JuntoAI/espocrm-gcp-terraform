${domain} {
    handle /ai-api/* {
        reverse_proxy ai-backend:3001
    }

    reverse_proxy espocrm:80

    reverse_proxy /ws espocrm-websocket:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }
}
