-- Tests for resumable exam attempts (migration 20260928140000_exam_attempt.sql).
-- Run with: supabase test db
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;

SELECT plan(28);

-- ---------------------------------------------------------------------------
-- Fixtures: two users, a published 30-minute exam with three questions, and a
-- private exam owned by user B.
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id, email, aud, role) VALUES
  ('11111111-1111-1111-1111-111111111111', 'attempt-a@example.test', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'attempt-b@example.test', 'authenticated', 'authenticated');

INSERT INTO public.question (id, content) VALUES
  (900001, 'Q1'), (900002, 'Q2'), (900003, 'Q3');

INSERT INTO public.exam (id, name, time_limit, publish, creator) VALUES
  (900100, 'Published exam', 30, true, '22222222-2222-2222-2222-222222222222'),
  (900200, 'Private exam of B', 60, false, '22222222-2222-2222-2222-222222222222');

-- Stored out of order to check the attempt snapshots them by "order"
INSERT INTO public.exam_question (exam_id, question_id, "order") VALUES
  (900100, 900003, 3), (900100, 900001, 1), (900100, 900002, 2);

CREATE TEMP TABLE ctx (key text PRIMARY KEY, value text);
GRANT ALL ON ctx TO authenticated, anon;

-- ---------------------------------------------------------------------------
-- Anonymous callers get nothing
-- ---------------------------------------------------------------------------
SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT public.start_exam_attempt(900100) $$, '42501', NULL,
  'anon cannot start an attempt');
SELECT throws_ok($$ SELECT public.get_exam_attempt(900100) $$, '42501', NULL,
  'anon cannot read an attempt');
SELECT throws_ok($$ SELECT count(*) FROM public.exam_attempt $$, '42501', NULL,
  'anon cannot select the table');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- User A starts and saves
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

INSERT INTO ctx SELECT 'a1', (public.start_exam_attempt(900100)->>'id');

SELECT is((public.get_exam_attempt(900100)->>'id'), (SELECT value FROM ctx WHERE key = 'a1'),
  'get_exam_attempt returns the open attempt');
SELECT is((public.get_exam_attempt(900100)->'question_ids')::text, '[900001,900002,900003]',
  'question order is snapshotted by exam_question.order');
SELECT is((public.get_exam_attempt(900100)->>'time_limit_seconds')::int, 1800,
  'time limit is snapshotted in seconds');
SELECT is((public.start_exam_attempt(900100)->>'id'), (SELECT value FROM ctx WHERE key = 'a1'),
  'starting again returns the same open attempt');

SELECT throws_ok($$ SELECT public.start_exam_attempt(900200) $$, 'P0002', 'Exam not found',
  'cannot start another user''s private exam');

SELECT lives_ok(format($$ SELECT public.save_attempt_progress(%L, '{"900001": 7}', ARRAY[900002]::bigint[], 900002, 100, 'aaaaaaaa-0000-0000-0000-000000000001') $$,
  (SELECT value FROM ctx WHERE key = 'a1')), 'saving progress works');
SELECT is((public.get_exam_attempt(900100)->'answers')::text, '{"900001": 7}', 'answers are saved');

SELECT is((public.save_attempt_progress((SELECT value FROM ctx WHERE key = 'a1')::uuid, '{}', '{}', 900001, 40, 'aaaaaaaa-0000-0000-0000-000000000001')->>'elapsed_seconds')::int,
  100, 'time used never goes backwards (a stale copy cannot wind the clock back)');
SELECT is((public.save_attempt_progress((SELECT value FROM ctx WHERE key = 'a1')::uuid, '{"900001": 7}', '{}', 900001, 99999, 'aaaaaaaa-0000-0000-0000-000000000001')->>'elapsed_seconds')::int,
  1800, 'time used is capped at the time limit');

SELECT throws_ok(format($$ SELECT public.save_attempt_progress(%L, '[1,2]', '{}', NULL, 0, 'aaaaaaaa-0000-0000-0000-000000000001') $$,
  (SELECT value FROM ctx WHERE key = 'a1')), '22023', NULL, 'answers must be a JSON object');

-- One page at a time: the one that last continued the attempt
SELECT throws_ok(format($$ SELECT public.save_attempt_progress(%L, '{}', '{}', NULL, 0, 'bbbbbbbb-0000-0000-0000-000000000002') $$,
  (SELECT value FROM ctx WHERE key = 'a1')), 'PT409', NULL, 'another page cannot save over the writer');
SELECT lives_ok(format($$ SELECT public.save_attempt_progress(%L, '{"900002": 8}', '{}', 900002, 0, 'bbbbbbbb-0000-0000-0000-000000000002', true) $$,
  (SELECT value FROM ctx WHERE key = 'a1')), 'continuing on another page claims the attempt');
SELECT throws_ok(format($$ SELECT public.save_attempt_progress(%L, '{"900001": 7}', '{}', 900001, 0, 'aaaaaaaa-0000-0000-0000-000000000001') $$,
  (SELECT value FROM ctx WHERE key = 'a1')), 'PT409', NULL, 'the old page can no longer save (a stale tab cannot erase newer answers)');
SELECT is((public.get_exam_attempt(900100)->'answers')::text, '{"900002": 8}', 'the newer answers are kept');
SELECT lives_ok(format($$ SELECT public.save_attempt_progress(%L, '{"900002": 8}', '{}', 900002, 0, 'bbbbbbbb-0000-0000-0000-000000000002') $$,
  (SELECT value FROM ctx WHERE key = 'a1')), 'the new writer keeps saving');

SELECT throws_ok($$ INSERT INTO public.exam_attempt (user_id, exam_id) VALUES ('11111111-1111-1111-1111-111111111111', 900100) $$,
  '42501', NULL, 'the table cannot be written directly');

-- ---------------------------------------------------------------------------
-- User B cannot see or touch A's attempt
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);

SELECT ok(public.get_exam_attempt(900100) IS NULL, 'another user does not see the attempt');
SELECT is((SELECT count(*) FROM public.exam_attempt)::int, 0, 'row level security hides other users'' attempts');
SELECT throws_ok(format($$ SELECT public.save_attempt_progress(%L, '{}', '{}', NULL, 0, 'cccccccc-0000-0000-0000-000000000003', true) $$,
  (SELECT value FROM ctx WHERE key = 'a1')), 'P0002', NULL, 'another user cannot save into the attempt, even claiming it');

-- ---------------------------------------------------------------------------
-- A submits: the attempt closes, and a retry does not add a second result
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

INSERT INTO ctx SELECT 'r1', public.save_exam_result(900100, 'Published exam', 33, 1, 3, 120, NULL, ARRAY[900002, 900003]::bigint[],
  (SELECT value FROM ctx WHERE key = 'a1')::uuid)->>'id';
SELECT ok(public.get_exam_attempt(900100) IS NULL, 'a submitted attempt is no longer open');

SELECT is(public.save_exam_result(900100, 'Published exam', 33, 1, 3, 120, NULL, ARRAY[900002, 900003]::bigint[],
  (SELECT value FROM ctx WHERE key = 'a1')::uuid)->>'id', (SELECT value FROM ctx WHERE key = 'r1'),
  'submitting the same attempt again returns the first result');
SELECT is((SELECT count(*) FROM public.exam_result WHERE exam_id = 900100)::int, 1,
  'the retry did not create a second result');

-- ---------------------------------------------------------------------------
-- A new attempt after submitting, then abandoning it
-- ---------------------------------------------------------------------------
INSERT INTO ctx SELECT 'a2', (public.start_exam_attempt(900100)->>'id');
SELECT isnt((SELECT value FROM ctx WHERE key = 'a2'), (SELECT value FROM ctx WHERE key = 'a1'),
  'after submitting, starting again opens a new attempt');

SELECT throws_ok(format($$ SELECT public.save_exam_result(900200, 'Private exam of B', 0, 0, 0, 0, NULL, NULL, %L) $$,
  (SELECT value FROM ctx WHERE key = 'a2')), '22023', NULL, 'a result cannot close an attempt of another exam');

SELECT public.abandon_exam_attempt((SELECT value FROM ctx WHERE key = 'a2')::uuid);
SELECT ok(public.get_exam_attempt(900100) IS NULL, 'an abandoned attempt is no longer open');

SELECT * FROM finish();
ROLLBACK;
