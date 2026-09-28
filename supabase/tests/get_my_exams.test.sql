-- Tests for get_my_exams() (migration 20260928150000_get_my_exams.sql).
-- Run with: supabase test db
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SET search_path = public, extensions;

SELECT plan(12);

-- A owns one exam; B publishes two, A takes one and has another in progress;
-- B also has a published exam A never touched.
INSERT INTO auth.users (id, email, aud, role) VALUES
  ('11111111-1111-1111-1111-111111111111', 'myexams-a@example.test', 'authenticated', 'authenticated'),
  ('22222222-2222-2222-2222-222222222222', 'myexams-b@example.test', 'authenticated', 'authenticated');

INSERT INTO public.question (id, content) VALUES (910001, 'Q1'), (910002, 'Q2'), (910003, 'Q3');

INSERT INTO public.exam (id, name, time_limit, publish, creator, created_at) VALUES
  (910100, 'A own exam',        60, false, '11111111-1111-1111-1111-111111111111', now() - interval '3 days'),
  (910200, 'B exam A took',     30, true,  '22222222-2222-2222-2222-222222222222', now() - interval '2 days'),
  (910300, 'B exam A is doing', 30, true,  '22222222-2222-2222-2222-222222222222', now() - interval '1 day'),
  (910400, 'B exam untouched',  30, true,  '22222222-2222-2222-2222-222222222222', now());

INSERT INTO public.exam_question (exam_id, question_id, "order") VALUES
  (910100, 910001, 1),
  (910200, 910001, 1), (910200, 910002, 2),
  (910300, 910001, 1), (910300, 910002, 2), (910300, 910003, 3);

INSERT INTO public.exam_result (user_id, exam_id, exam_name, score, correct_count, total_count, duration_seconds, completed_at) VALUES
  ('11111111-1111-1111-1111-111111111111', 910200, 'B exam A took', 50, 1, 2, 90,  now() - interval '5 hours'),
  ('11111111-1111-1111-1111-111111111111', 910200, 'B exam A took', 100, 2, 2, 60, now() - interval '1 hour'),
  ('22222222-2222-2222-2222-222222222222', 910100, 'A own exam', 0, 0, 1, 10, now());

INSERT INTO public.exam_attempt (user_id, exam_id, question_ids, answers, flagged, current_question_id, elapsed_seconds, time_limit_seconds) VALUES
  ('11111111-1111-1111-1111-111111111111', 910300, ARRAY[910001, 910002, 910003]::bigint[], '{"910001": 1, "910002": 2}', ARRAY[910002]::bigint[], 910003, 300, 1800);

CREATE TEMP TABLE mine AS SELECT NULL::json AS data;
GRANT ALL ON mine TO authenticated, anon;

SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT public.get_my_exams() $$, '42501', NULL, 'anon cannot call get_my_exams');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
UPDATE mine SET data = public.get_my_exams();

SELECT is((SELECT json_agg(e->>'name')::text FROM mine, json_array_elements(data) e),
  '["B exam A is doing", "B exam A took", "A own exam"]',
  'lists own, taken and in-progress exams, newest first, and not others'' untouched ones');

SELECT is((SELECT (e->>'is_owner')::boolean FROM mine, json_array_elements(data) e WHERE e->>'name' = 'A own exam'), true, 'own exam is marked as owned');
SELECT is((SELECT (e->>'is_owner')::boolean FROM mine, json_array_elements(data) e WHERE e->>'name' = 'B exam A took'), false, 'someone else''s exam is not owned');
SELECT is((SELECT (e->>'question_count')::int FROM mine, json_array_elements(data) e WHERE e->>'name' = 'B exam A is doing'), 3, 'question count');

SELECT is((SELECT (e->'last_result'->>'correct_count')::int FROM mine, json_array_elements(data) e WHERE e->>'name' = 'B exam A took'), 2, 'last_result is the latest result');
SELECT ok((SELECT e->'last_result' IS NULL OR json_typeof(e->'last_result') = 'null' FROM mine, json_array_elements(data) e WHERE e->>'name' = 'A own exam'),
  'another user''s result on my exam is not mine');

SELECT is((SELECT (e->'open_attempt'->>'answered_count')::int FROM mine, json_array_elements(data) e WHERE e->>'name' = 'B exam A is doing'), 2, 'open attempt: answered count');
SELECT is((SELECT (e->'open_attempt'->>'current_position')::int FROM mine, json_array_elements(data) e WHERE e->>'name' = 'B exam A is doing'), 3, 'open attempt: 1-based position of the current question');
SELECT is((SELECT (e->'open_attempt'->>'flagged_count')::int FROM mine, json_array_elements(data) e WHERE e->>'name' = 'B exam A is doing'), 1, 'open attempt: flagged count');
SELECT ok((SELECT json_typeof(e->'open_attempt') = 'null' FROM mine, json_array_elements(data) e WHERE e->>'name' = 'B exam A took'), 'no open attempt when none is in progress');

SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
SELECT is((SELECT json_array_length(public.get_my_exams())), 4, 'B sees the three exams B created plus the one B took');

SELECT * FROM finish();
ROLLBACK;
