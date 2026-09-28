-- Migration: get_my_exams() for the 我的考卷 page
-- =============================================================================
-- Everything the page needs in one call: the exams the user created, plus the
-- ones they have taken or have in progress. Other users' published exams are
-- not listed here (they are browsed in 練習模式 > 考卷列表).
--
-- For each exam: question count, whether the user owns it (only owners can
-- delete), the unfinished attempt if any, and the latest result.

CREATE OR REPLACE FUNCTION public.get_my_exams()
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_result json;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;

  SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at DESC, t.id DESC), '[]'::json)
  INTO v_result
  FROM (
    SELECT
      e.id,
      e.name,
      e.description,
      e.time_limit,
      e.publish,
      e.created_at,
      (e.creator = v_uid) AS is_owner,
      (SELECT count(*) FROM exam_question eq WHERE eq.exam_id = e.id)::int AS question_count,
      (
        SELECT json_build_object(
          'id', a.id,
          'answered_count', (SELECT count(*) FROM jsonb_object_keys(a.answers))::int,
          'question_count', COALESCE(array_length(a.question_ids, 1), 0),
          'flagged_count', COALESCE(array_length(a.flagged, 1), 0),
          'current_position', COALESCE(array_position(a.question_ids, a.current_question_id), 1),
          'elapsed_seconds', a.elapsed_seconds,
          'time_limit_seconds', a.time_limit_seconds,
          'updated_at', a.updated_at
        )
        FROM exam_attempt a
        WHERE a.exam_id = e.id AND a.user_id = v_uid AND a.status = 'in_progress'
      ) AS open_attempt,
      (
        SELECT json_build_object(
          'id', r.id,
          'correct_count', r.correct_count,
          'total_count', r.total_count,
          'score', r.score,
          'duration_seconds', r.duration_seconds,
          'completed_at', r.completed_at
        )
        FROM exam_result r
        WHERE r.exam_id = e.id AND r.user_id = v_uid
        ORDER BY r.completed_at DESC, r.id DESC
        LIMIT 1
      ) AS last_result
    FROM exam e
    WHERE e.creator = v_uid
       OR EXISTS (SELECT 1 FROM exam_result r WHERE r.exam_id = e.id AND r.user_id = v_uid)
       OR EXISTS (SELECT 1 FROM exam_attempt a WHERE a.exam_id = e.id AND a.user_id = v_uid AND a.status = 'in_progress')
  ) t;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_exams() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_exams() TO authenticated;
