# Bankal

Personal kanban board built with Zig + Alpine.js. Uses event sourcing/CQRS.

## Features

- Multiple boards
- Drag & drop cards
- Event-sourced persistence (append-only WAL)
- Single binary, embeds frontend

## Prerequisites

- Zig 0.15.2 (later might break it)
- Bun (for bundling frontend)

## Build & Run

```bash
cd static/ && bun install
zig build run
```

Server runs on `localhost:8080`. WAL file created automatically.

## Deployment

Put behind nginx/caddy with auth or keep on localhost. 

## API

Simple REST, all JSON:

```
GET  /api/boards              - list boards
POST /api/boards              - create board
GET  /api/boards/:id/cards    - cards for board
POST /api/cards               - create card
PATCH /api/cards/:id          - update card
PATCH /api/cards/:id/column   - move column
PATCH /api/cards/:id/board    - move board
```

## Architecture

Event sourcing: all changes = events appended to WAL. State is rebuilt from events on startup, which works well enough for small scale.

## License

AGPL-3.0
Alpine.js is MIT licensed (see LICENSES).
