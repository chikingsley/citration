set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

lint-swift:
    bun run lint:swift

lint-swift-fix:
    bun run lint:swift:fix

test-swift:
    bun run test:swift

check-swift:
    bun run check:swift

commit-swift +args:
    bun run commit:swift -- {{args}}

dev-backend:
    cd backend && bun run dev

deploy-backend:
    cd backend && bun run deploy

db-migrate-local:
    cd backend && bun run db:migrate:local

db-migrate:
    cd backend && bun run db:migrate

typecheck-backend:
    cd backend && bunx tsc --noEmit
