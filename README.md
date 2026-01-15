# Bankal

Personal kanban board built with Zig + Alpine.js.

## Features

- Multiple boards
- Drag & drop cards
- Simple wal file persistence
- Single binary, embeds frontend

## Prerequisites

- Zig 0.15.2 
- Bun (for bundling frontend)

## Dependencies

HTTP server and WAL persistence live in `src/vendor/` as git submodules:

- `event_wal` - append-only WAL + thread-safe storage
- `http_common` - minimal HTTP router/server

Clone with submodules:
```bash
git clone --recurse-submodules https://github.com/yourusername/kanban.git
```

Or if you already cloned:
```bash
git submodule update --init --recursive
```

## Build & Run

```bash
zig build run
```

zig build will have bun install frontend dependencies and bundle frontend.

Server runs on `localhost:8080`. The database will be created automatically.

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

## License

AGPL-3.0

Third-party licenses in `LICENSES/`:
- Alpine.js (MIT)
- DOMPurify (Apache-2.0 or MPL-2.0)
- Marked (MIT)
