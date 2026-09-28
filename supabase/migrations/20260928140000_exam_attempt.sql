-- Migration: exam attempts that can be resumed
-- =============================================================================
-- An exam_attempt row is one sitting of an exam. While it is in progress it
-- holds the answers, flags, current position and the time actually spent
-- answering, so a user can leave and continue later, on any device.
--
-- Time is stored as elapsed_seconds (time spent with the exam page visible),
-- not a start timestamp: the timer is paused while the user is away.
-- An in-progress attempt never expires; it ends when submitted or abandoned.
--
-- Only one page writes an attempt at a time: the one that last continued it.
-- Each exam page has a random writer id; continuing an attempt from the resume
-- prompt claims it, and saves from any other page (an old tab, another device)
-- are then refused, so a stale copy can't overwrite newer answers.
--
-- All writes go through the SECURITY DEFINER functions below. Each one takes
-- the user from auth.uid() (never from an argument), and none is executable
-- by anon or PUBLIC.

CREATE TABLE IF NOT EXISTS public.exam_attempt (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  exam_id             bigint NOT NULL REFERENCES public.exam (id) ON DELETE CASCADE,
  status              text NOT NULL DEFAULT 'in_progress'
                        CHECK (status IN ('in_progress', 'submitted', 'abandoned')),
  -- Question order when the attempt started. The client maps answers by question
  -- id onto the exam's current questions, so this is a record, not the source.
  question_ids        bigint[] NOT NULL DEFAULT '{}',
  answers             jsonb NOT NULL DEFAULT '{}'::jsonb
                        CHECK (jsonb_typeof(answers) = 'object'),   -- { "<question_id>": <option_id> }
  flagged             bigint[] NOT NULL DEFAULT '{}',
  current_question_id bigint,
  elapsed_seconds     integer NOT NULL DEFAULT 0 CHECK (elapsed_seconds >= 0),
  time_limit_seconds  integer CHECK (time_limit_seconds IS NULL OR time_limit_seconds > 0),
  result_id           bigint REFERENCES public.exam_result (id) ON DELETE SET NULL,
  started_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  finished_at         timestamptz,
  -- The page (tab/device) that last continued the attempt; see save_attempt_progress
  writer_id           uuid
);

COMMENT ON TABLE public.exam_attempt IS 'One sitting of an exam; in_progress rows can be resumed';
COMMENT ON COLUMN public.exam_attempt.elapsed_seconds IS 'Time spent with the exam visible; pauses while the user is away';

-- At most one open attempt per user and exam (different exams can each have one).
CREATE UNIQUE INDEX IF NOT EXISTS exam_attempt_one_open_per_exam
  ON public.exam_attempt (user_id, exam_id) WHERE status = 'in_progress';
CREATE INDEX IF NOT EXISTS exam_attempt_user_recent
  ON public.exam_attempt (user_id, updated_at DESC);

ALTER TABLE public.exam_attempt ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own exam attempts" ON public.exam_attempt;
CREATE POLICY "Users read own exam attempts" ON public.exam_attempt
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
-- No insert/update/delete policies: writes only happen through the functions below.

REVOKE ALL ON TABLE public.exam_attempt FROM anon, PUBLIC;
GRANT SELECT ON TABLE public.exam_attempt TO authenticated;
GRANT ALL ON TABLE public.exam_attempt TO service_role;


-- Shape returned to the client
CREATE OR REPLACE FUNCTION public.exam_attempt_json(a public.exam_attempt)
RETURNS json
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT json_build_object(
    'id', a.id,
    'exam_id', a.exam_id,
    'status', a.status,
    'question_ids', a.question_ids,
    'answers', a.answers,
    'flagged', a.flagged,
    'current_question_id', a.current_question_id,
    'elapsed_seconds', a.elapsed_seconds,
    'time_limit_seconds', a.time_limit_seconds,
    'started_at', a.started_at,
    'updated_at', a.updated_at
  );
$$;


-- The caller's unfinished attempt for an exam, or null.
CREATE OR REPLACE FUNCTION public.get_exam_attempt(p_exam_id bigint)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_attempt public.exam_attempt;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;

  SELECT * INTO v_attempt FROM public.exam_attempt
  WHERE user_id = v_uid AND exam_id = p_exam_id AND status = 'in_progress';

  RETURN CASE WHEN v_attempt.id IS NULL THEN NULL ELSE public.exam_attempt_json(v_attempt) END;
END;
$$;


-- Start an attempt, or return the one already open for this exam.
CREATE OR REPLACE FUNCTION public.start_exam_attempt(p_exam_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_exam public.exam;
  v_attempt public.exam_attempt;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;

  -- Same visibility as get_practice_exams: published, or the caller's own
  SELECT * INTO v_exam FROM public.exam
  WHERE id = p_exam_id AND (publish = true OR creator = v_uid);
  IF v_exam.id IS NULL THEN RAISE EXCEPTION 'Exam not found' USING ERRCODE = 'P0002'; END IF;

  INSERT INTO public.exam_attempt (user_id, exam_id, question_ids, time_limit_seconds)
  VALUES (
    v_uid,
    p_exam_id,
    COALESCE((SELECT array_agg(eq.question_id ORDER BY eq."order", eq.id)
              FROM public.exam_question eq WHERE eq.exam_id = p_exam_id), '{}'),
    CASE WHEN v_exam.time_limit > 0 THEN v_exam.time_limit * 60 END
  )
  ON CONFLICT (user_id, exam_id) WHERE status = 'in_progress' DO NOTHING;

  SELECT * INTO v_attempt FROM public.exam_attempt
  WHERE user_id = v_uid AND exam_id = p_exam_id AND status = 'in_progress';

  RETURN public.exam_attempt_json(v_attempt);
END;
$$;


-- Save progress. Time used only moves forward and never past the limit.
-- p_writer_id is the calling page. A page may save while it is the attempt's
-- writer (or no page has saved yet); p_claim takes the attempt over, which is
-- what continuing it from the resume prompt does. Any other page gets PT409
-- (HTTP 409): the attempt is being continued elsewhere.
CREATE OR REPLACE FUNCTION public.save_attempt_progress(
  p_attempt_id uuid,
  p_answers jsonb,
  p_flagged bigint[],
  p_current_question_id bigint,
  p_elapsed_seconds integer,
  p_writer_id uuid,
  p_claim boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_attempt public.exam_attempt;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'object' THEN
    RAISE EXCEPTION 'answers must be a JSON object' USING ERRCODE = '22023';
  END IF;
  IF p_writer_id IS NULL THEN
    RAISE EXCEPTION 'writer id is required' USING ERRCODE = '22023';
  END IF;

  UPDATE public.exam_attempt a SET
    answers = p_answers,
    flagged = COALESCE(p_flagged, '{}'),
    current_question_id = p_current_question_id,
    elapsed_seconds = LEAST(
      GREATEST(a.elapsed_seconds, COALESCE(p_elapsed_seconds, 0)),
      COALESCE(a.time_limit_seconds, 2147483647)
    ),
    writer_id = p_writer_id,
    updated_at = now()
  WHERE a.id = p_attempt_id AND a.user_id = v_uid AND a.status = 'in_progress'
    AND (p_claim OR a.writer_id IS NULL OR a.writer_id = p_writer_id)
  RETURNING * INTO v_attempt;

  IF v_attempt.id IS NULL THEN
    IF EXISTS (SELECT 1 FROM public.exam_attempt
               WHERE id = p_attempt_id AND user_id = v_uid AND status = 'in_progress') THEN
      RAISE EXCEPTION 'Attempt is being continued elsewhere' USING ERRCODE = 'PT409';
    END IF;
    RAISE EXCEPTION 'Attempt not found or already finished' USING ERRCODE = 'P0002';
  END IF;

  RETURN json_build_object('updated_at', v_attempt.updated_at, 'elapsed_seconds', v_attempt.elapsed_seconds);
END;
$$;


-- Abandon an unfinished attempt ("放棄" / "重新開始").
CREATE OR REPLACE FUNCTION public.abandon_exam_attempt(p_attempt_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;

  UPDATE public.exam_attempt
  SET status = 'abandoned', finished_at = now(), updated_at = now()
  WHERE id = p_attempt_id AND user_id = auth.uid() AND status = 'in_progress';
END;
$$;


-- save_exam_result gains p_attempt_id: the result is written and the attempt is
-- closed in one transaction. Submitting the same attempt twice (e.g. a retry
-- after a dropped response) returns the first result instead of adding another.
-- The attempt must be for the same exam. One that was abandoned elsewhere, or no
-- longer exists, doesn't stop the result being saved: the exam was finished here.
DROP FUNCTION IF EXISTS public.save_exam_result(bigint, text, numeric, integer, integer, integer, jsonb, bigint[]);

CREATE OR REPLACE FUNCTION public.save_exam_result(
  p_exam_id bigint DEFAULT NULL,
  p_exam_name text DEFAULT '',
  p_score numeric DEFAULT 0,
  p_correct_count integer DEFAULT 0,
  p_total_count integer DEFAULT 0,
  p_duration_seconds integer DEFAULT NULL,
  p_answers_json jsonb DEFAULT NULL,
  p_wrong_question_ids bigint[] DEFAULT NULL,
  p_attempt_id uuid DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid := auth.uid();
  v_result_id bigint;
  wq_id bigint;
  v_attempt public.exam_attempt;
BEGIN
  IF current_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  IF p_attempt_id IS NOT NULL THEN
    SELECT * INTO v_attempt FROM public.exam_attempt
    WHERE id = p_attempt_id AND user_id = current_user_id
    FOR UPDATE;

    IF v_attempt.id IS NOT NULL AND v_attempt.exam_id IS DISTINCT FROM p_exam_id THEN
      RAISE EXCEPTION 'Attempt belongs to another exam' USING ERRCODE = '22023';
    END IF;

    IF v_attempt.status = 'submitted' AND v_attempt.result_id IS NOT NULL THEN
      RETURN json_build_object('id', v_attempt.result_id, 'success', true, 'duplicate', true);
    END IF;
  END IF;

  INSERT INTO exam_result (user_id, exam_id, exam_name, score, correct_count, total_count, duration_seconds, answers_json)
  VALUES (current_user_id, p_exam_id, p_exam_name, p_score, p_correct_count, p_total_count, p_duration_seconds, p_answers_json)
  RETURNING id INTO v_result_id;

  IF p_wrong_question_ids IS NOT NULL THEN
    FOREACH wq_id IN ARRAY p_wrong_question_ids LOOP
      INSERT INTO wrong_question (user_id, question_id, wrong_count, last_wrong_at)
      VALUES (current_user_id, wq_id, 1, NOW())
      ON CONFLICT (user_id, question_id) DO UPDATE
        SET wrong_count = wrong_question.wrong_count + 1, last_wrong_at = NOW(), reviewed = FALSE;
    END LOOP;
  END IF;

  IF v_attempt.id IS NOT NULL AND v_attempt.status = 'in_progress' THEN
    UPDATE public.exam_attempt SET
      status = 'submitted',
      result_id = v_result_id,
      elapsed_seconds = GREATEST(elapsed_seconds, COALESCE(p_duration_seconds, 0)),
      finished_at = now(),
      updated_at = now()
    WHERE id = v_attempt.id;
  END IF;

  RETURN json_build_object('id', v_result_id, 'success', true);
END;
$$;


-- Only signed-in users can call these; PostgreSQL grants EXECUTE to PUBLIC by default.
REVOKE ALL ON FUNCTION public.exam_attempt_json(public.exam_attempt) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_exam_attempt(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.start_exam_attempt(bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_attempt_progress(uuid, jsonb, bigint[], bigint, integer, uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.abandon_exam_attempt(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.save_exam_result(bigint, text, numeric, integer, integer, integer, jsonb, bigint[], uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_exam_attempt(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_exam_attempt(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_attempt_progress(uuid, jsonb, bigint[], bigint, integer, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.abandon_exam_attempt(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_exam_result(bigint, text, numeric, integer, integer, integer, jsonb, bigint[], uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exam_attempt_json(public.exam_attempt) TO service_role;
