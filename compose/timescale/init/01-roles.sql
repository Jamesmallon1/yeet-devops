-- Runs once on first boot (docker-entrypoint-initdb.d). Passwords injected via env by the entrypoint shell wrapper.
\set indexer_pw `echo "$TS_INDEXER_PASSWORD"`
\set api_pw     `echo "$TS_API_PASSWORD"`
\set monolith   `echo "$MONOLITH_IP"`

CREATE ROLE yeet_indexer LOGIN PASSWORD :'indexer_pw';
CREATE ROLE yeet_api     LOGIN PASSWORD :'api_pw';

CREATE DATABASE yeet_ts OWNER yeet_indexer;
\connect yeet_ts
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

GRANT CONNECT ON DATABASE yeet_ts TO yeet_api;
GRANT USAGE ON SCHEMA public TO yeet_api;
ALTER DEFAULT PRIVILEGES FOR ROLE yeet_indexer IN SCHEMA public GRANT SELECT ON TABLES TO yeet_api;
ALTER ROLE yeet_api SET statement_timeout = '2s';
ALTER ROLE yeet_api SET default_transaction_read_only = on;
ALTER ROLE yeet_indexer SET synchronous_commit = off;

