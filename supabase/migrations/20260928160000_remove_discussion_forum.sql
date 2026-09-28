-- Migration: remove the discussion forum
-- =============================================================================
-- The discussion forum (20260120_discussion_forum_mvp.sql) has been removed
-- from the app, so drop its tables, RPCs and triggers.
--
-- user_credits_mvp stays: it also holds display_name, which get_user_profile,
-- update_user_display_name and the sign-up trigger (initialize_user_credits_mvp)
-- still use. Its credits/reputation columns are no longer read by the app.

DROP FUNCTION IF EXISTS public.get_discussions_mvp(integer, integer);
DROP FUNCTION IF EXISTS public.get_discussion_detail_mvp(uuid, uuid);
DROP FUNCTION IF EXISTS public.unlock_answer_mvp(uuid, uuid);
DROP FUNCTION IF EXISTS public.cast_vote_mvp(uuid, uuid, integer);
DROP FUNCTION IF EXISTS public.claim_daily_credits_mvp(uuid);
DROP FUNCTION IF EXISTS public.get_user_credits_mvp(uuid);

-- Dropping answers_mvp also drops trigger_update_answer_count_mvp.
DROP TABLE IF EXISTS public.votes_mvp;
DROP TABLE IF EXISTS public.unlocks_mvp;
DROP TABLE IF EXISTS public.answers_mvp;
DROP TABLE IF EXISTS public.discussions_mvp;

DROP FUNCTION IF EXISTS public.update_answer_count_mvp();
