-- Tests for 20260928130100_secure_note_and_extension_rpcs.sql: the note and
-- extension-sync RPCs only reach the caller's own data.
-- Run with: supabase test db
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;

SELECT plan(24);

INSERT INTO auth.users (id, email, aud, role) VALUES
  ('11111111-1111-1111-1111-111111111111', 'notes-a@example.test', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'notes-b@example.test', 'authenticated', 'authenticated');

CREATE TEMP TABLE ctx (key text PRIMARY KEY, value text);
GRANT ALL ON ctx TO authenticated, anon, service_role;

CREATE TEMP VIEW zero AS SELECT array_fill(0::real, ARRAY[1536])::vector AS v;
GRANT SELECT ON zero TO authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- Anonymous callers can't run any of them
-- ---------------------------------------------------------------------------
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT public.get_notes_summary('11111111-1111-1111-1111-111111111111') $$, '42501', NULL,
  'anon cannot read notes');
SELECT throws_ok($$ SELECT public.get_user_conversations('11111111-1111-1111-1111-111111111111') $$, '42501', NULL,
  'anon cannot list conversations');
SELECT throws_ok($$ SELECT public.sync_extension_session('11111111-1111-1111-1111-111111111111', gen_random_uuid(), NULL, 't') $$, '42501', NULL,
  'anon cannot sync a session');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- A signed-in user reaches only their own data
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

SELECT lives_ok($$ SELECT public.get_notes_summary('11111111-1111-1111-1111-111111111111') $$, 'own notes summary');
SELECT lives_ok($$ SELECT public.get_recent_notes('11111111-1111-1111-1111-111111111111') $$, 'own recent notes');
SELECT lives_ok($$ SELECT public.search_all_notes('11111111-1111-1111-1111-111111111111', 'x') $$, 'own note search');
SELECT lives_ok($$ SELECT public.get_unified_ai_context('11111111-1111-1111-1111-111111111111', (SELECT v FROM zero)) $$, 'own AI context');
SELECT lives_ok($$ SELECT * FROM public.match_exam_notes('11111111-1111-1111-1111-111111111111', (SELECT v FROM zero)) $$, 'own exam note match');
SELECT lives_ok($$ SELECT * FROM public.match_legal_notes('11111111-1111-1111-1111-111111111111', (SELECT v FROM zero)) $$, 'own legal note match');
SELECT lives_ok($$ SELECT public.get_legal_notes_by_source('11111111-1111-1111-1111-111111111111', 'judgment') $$, 'own legal notes by source');

SELECT throws_ok($$ SELECT public.get_notes_summary('22222222-2222-2222-2222-222222222222') $$, '42501', NULL,
  'another user''s notes summary is refused');
SELECT throws_ok($$ SELECT public.get_unified_ai_context('22222222-2222-2222-2222-222222222222', (SELECT v FROM zero)) $$, '42501', NULL,
  'another user''s AI context is refused');
SELECT throws_ok($$ SELECT * FROM public.match_legal_notes('22222222-2222-2222-2222-222222222222', (SELECT v FROM zero)) $$, '42501', NULL,
  'another user''s legal notes are refused');
SELECT throws_ok($$ SELECT * FROM public.get_user_conversations('22222222-2222-2222-2222-222222222222') $$, '42501', NULL,
  'another user''s conversations are refused');
SELECT throws_ok($$ SELECT public.link_local_sessions_to_user('22222222-2222-2222-2222-222222222222', 'local-x') $$, '42501', NULL,
  'cannot link sessions to another user');
SELECT throws_ok($$ SELECT public.upsert_legal_note_embedding(gen_random_uuid(), (SELECT v FROM zero)) $$, '42501', NULL,
  'embeddings are written by the service role only');

-- ---------------------------------------------------------------------------
-- Extension sync: idempotent for the owner, closed to everyone else
-- ---------------------------------------------------------------------------
INSERT INTO ctx SELECT 'ext', gen_random_uuid()::text;
INSERT INTO ctx SELECT 'c1', public.sync_extension_session('11111111-1111-1111-1111-111111111111',
  (SELECT value FROM ctx WHERE key = 'ext')::uuid, 'local-a', 'First title')::text;
SELECT is(public.sync_extension_session('11111111-1111-1111-1111-111111111111',
  (SELECT value FROM ctx WHERE key = 'ext')::uuid, 'local-a', 'Renamed')::text, (SELECT value FROM ctx WHERE key = 'c1'),
  'syncing the same session again updates it');
SELECT is((SELECT count(*) FROM public.get_user_conversations('11111111-1111-1111-1111-111111111111'))::int, 1,
  'and does not create a second conversation');

INSERT INTO ctx SELECT 'msg', gen_random_uuid()::text;
INSERT INTO ctx SELECT 'm1', public.sync_extension_message((SELECT value FROM ctx WHERE key = 'c1')::uuid,
  (SELECT value FROM ctx WHERE key = 'msg')::uuid, 'user', 'hello')::text;
SELECT is(public.sync_extension_message((SELECT value FROM ctx WHERE key = 'c1')::uuid,
  (SELECT value FROM ctx WHERE key = 'msg')::uuid, 'user', 'hello')::text, (SELECT value FROM ctx WHERE key = 'm1'),
  'syncing the same message again returns it');

SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
SELECT throws_ok(format($$ SELECT public.sync_extension_session('22222222-2222-2222-2222-222222222222', %L, 'local-b', 'Hijack') $$,
  (SELECT value FROM ctx WHERE key = 'ext')), '42501', NULL, 'another user cannot take over a synced session');
SELECT throws_ok(format($$ SELECT public.sync_extension_message(%L, gen_random_uuid(), 'user', 'injected') $$,
  (SELECT value FROM ctx WHERE key = 'c1')), '42501', NULL, 'another user cannot write into the conversation');
SELECT throws_ok($$ SELECT public.sync_extension_session('11111111-1111-1111-1111-111111111111', gen_random_uuid(), NULL, 't') $$, '42501', NULL,
  'cannot sync a session as another user');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- The service role may act for any user
-- ---------------------------------------------------------------------------
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT lives_ok($$ SELECT public.get_notes_summary('22222222-2222-2222-2222-222222222222') $$, 'the service role reads any user''s summary');
RESET ROLE;

SELECT is((SELECT title FROM public.conversation WHERE id = (SELECT value FROM ctx WHERE key = 'c1')::uuid)::text, 'Renamed',
  'the owner''s update went through');

SELECT * FROM finish();
ROLLBACK;
