-- Migration: only a user's own notes and conversations through the note/extension RPCs
-- =============================================================================
-- These SECURITY DEFINER functions take the target user as p_user_id and were
-- executable by PUBLIC (including anon), so any caller could read another
-- user's exam notes, legal notes and conversations, or write into their
-- conversations, through /rest/v1/rpc. See the SECURITY NOTE in
-- 20260928130000_capture_extension_sync_schema.sql.
--
-- Their callers (this app and the Precedent extension) call them with the
-- user's own JWT and pass that user's id, so the signatures stay as they are:
--   * p_user_id must now be the caller (auth.uid()); the service role, which
--     bypasses RLS anyway, may still act for any user.
--   * sync_extension_message only writes into the caller's own conversation.
--   * the embedding upserts are for the service role only.
--   * nothing here is executable by PUBLIC or anon any more.
-- The two sync functions also become safe against concurrent/retried delivery
-- (they used to SELECT and then INSERT, racing on the external_id indexes).

CREATE OR REPLACE FUNCTION public.assert_caller_is(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
    IF auth.role() = 'service_role' THEN
        RETURN;
    END IF;
    IF auth.uid() IS NULL OR p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Not allowed for another user' USING ERRCODE = '42501';
    END IF;
END;
$$;

COMMENT ON FUNCTION public.assert_caller_is(uuid) IS 'Raises 42501 unless p_user_id is the calling user (or the caller is the service role)';


-- -----------------------------------------------------------------------------
-- Readers that take p_user_id: copied unchanged, apart from the check on their
-- first line. search_all_notes also had its ORDER BY/LIMIT outside json_agg,
-- which made every call fail ("must appear in the GROUP BY clause"); they now
-- sit in a subquery.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_unified_ai_context(
    p_user_id UUID,
    query_embedding vector(1536),
    p_threshold float DEFAULT 0.65,
    p_max_per_source int DEFAULT 5
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result JSON;
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    SELECT json_build_object(
        'exam_notes', COALESCE((
            SELECT json_agg(json_build_object(
                'id', n.id,
                'title', n.title,
                'content', n.content,
                'source_type', n.source_type,
                'source_metadata', n.source_metadata,
                'tags', n.tags,
                'similarity', 1 - (ne.embedding <=> query_embedding),
                'created_at', n.created_at
            ) ORDER BY ne.embedding <=> query_embedding)
            FROM public.exam_note n
            JOIN public.exam_note_embedding ne ON ne.note_id = n.id
            WHERE n.user_id = p_user_id
            AND n.is_archived = false
            AND 1 - (ne.embedding <=> query_embedding) > p_threshold
            LIMIT p_max_per_source
        ), '[]'::json),
        'legal_notes', COALESCE((
            SELECT json_agg(json_build_object(
                'id', n.id,
                'title', n.title,
                'content', n.content,
                'highlighted_text', n.highlighted_text,
                'source_type', n.source_type,
                'source_url', n.source_url,
                'source_metadata', n.source_metadata,
                'tags', n.tags,
                'similarity', 1 - (ne.embedding <=> query_embedding),
                'created_at', n.created_at
            ) ORDER BY ne.embedding <=> query_embedding)
            FROM public.legal_note n
            JOIN public.legal_note_embedding ne ON ne.note_id = n.id
            WHERE n.user_id = p_user_id
            AND n.is_archived = false
            AND 1 - (ne.embedding <=> query_embedding) > p_threshold
            LIMIT p_max_per_source
        ), '[]'::json),
        'questions', COALESCE((
            SELECT json_agg(json_build_object(
                'id', q.id,
                'content', q.content,
                'subject', q.subject,
                'year', q.year,
                'difficulty', q.difficulty,
                'similarity', 1 - (qe.embedding <=> query_embedding),
                'created_at', q.created_at
            ) ORDER BY qe.embedding <=> query_embedding)
            FROM public.question q
            JOIN public.question_embedding qe ON qe.question_id = q.id
            WHERE 1 - (qe.embedding <=> query_embedding) > p_threshold
            LIMIT p_max_per_source
        ), '[]'::json)
    ) INTO result;

    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.search_all_notes(
    p_user_id UUID,
    p_search_query TEXT,
    p_limit int DEFAULT 20
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result JSON;
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    SELECT json_build_object(
        'exam_notes', COALESCE((
            SELECT json_agg(json_build_object(
                'id', n.id,
                'title', n.title,
                'content', n.content,
                'source_type', n.source_type,
                'tags', n.tags,
                'created_at', n.created_at,
                'source', 'exam'
            ) ORDER BY n.created_at DESC)
            FROM (
                SELECT * FROM public.exam_note n
                WHERE n.user_id = p_user_id
                AND n.is_archived = false
                AND (
                    n.title ILIKE '%' || p_search_query || '%'
                    OR n.content ILIKE '%' || p_search_query || '%'
                    OR p_search_query = ANY(n.tags)
                )
                ORDER BY n.created_at DESC
                LIMIT p_limit
            ) n
        ), '[]'::json),
        'legal_notes', COALESCE((
            SELECT json_agg(json_build_object(
                'id', n.id,
                'title', n.title,
                'content', n.content,
                'highlighted_text', n.highlighted_text,
                'source_type', n.source_type,
                'tags', n.tags,
                'created_at', n.created_at,
                'source', 'legal'
            ) ORDER BY n.created_at DESC)
            FROM (
                SELECT * FROM public.legal_note n
                WHERE n.user_id = p_user_id
                AND n.is_archived = false
                AND (
                    n.title ILIKE '%' || p_search_query || '%'
                    OR n.content ILIKE '%' || p_search_query || '%'
                    OR n.highlighted_text ILIKE '%' || p_search_query || '%'
                    OR p_search_query = ANY(n.tags)
                )
                ORDER BY n.created_at DESC
                LIMIT p_limit
            ) n
        ), '[]'::json)
    ) INTO result;

    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_notes_summary(
    p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result JSON;
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    SELECT json_build_object(
        'exam_notes', json_build_object(
            'total', COALESCE((SELECT COUNT(*) FROM public.exam_note WHERE user_id = p_user_id AND is_archived = false), 0),
            'pinned', COALESCE((SELECT COUNT(*) FROM public.exam_note WHERE user_id = p_user_id AND is_pinned = true AND is_archived = false), 0),
            'with_flashcards', COALESCE((
                SELECT COUNT(DISTINCT note_id)
                FROM public.exam_note_flashcard
                WHERE user_id = p_user_id
            ), 0),
            'by_source_type', COALESCE((
                SELECT json_object_agg(source_type, count)
                FROM (
                    SELECT source_type, COUNT(*) as count
                    FROM public.exam_note
                    WHERE user_id = p_user_id AND is_archived = false
                    GROUP BY source_type
                ) sub
            ), '{}'::json)
        ),
        'legal_notes', json_build_object(
            'total', COALESCE((SELECT COUNT(*) FROM public.legal_note WHERE user_id = p_user_id AND is_archived = false), 0),
            'pinned', COALESCE((SELECT COUNT(*) FROM public.legal_note WHERE user_id = p_user_id AND is_pinned = true AND is_archived = false), 0),
            'with_flashcards', COALESCE((
                SELECT COUNT(DISTINCT note_id)
                FROM public.legal_note_flashcard
                WHERE user_id = p_user_id
            ), 0),
            'by_source_type', COALESCE((
                SELECT json_object_agg(source_type, count)
                FROM (
                    SELECT source_type, COUNT(*) as count
                    FROM public.legal_note
                    WHERE user_id = p_user_id AND is_archived = false
                    GROUP BY source_type
                ) sub
            ), '{}'::json)
        ),
        'combined', json_build_object(
            'total_notes', COALESCE((
                SELECT COUNT(*) FROM public.exam_note WHERE user_id = p_user_id AND is_archived = false
            ), 0) + COALESCE((
                SELECT COUNT(*) FROM public.legal_note WHERE user_id = p_user_id AND is_archived = false
            ), 0),
            'total_flashcards', COALESCE((
                SELECT COUNT(*) FROM public.exam_note_flashcard WHERE user_id = p_user_id
            ), 0) + COALESCE((
                SELECT COUNT(*) FROM public.legal_note_flashcard WHERE user_id = p_user_id
            ), 0)
        )
    ) INTO result;

    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_recent_notes(
    p_user_id UUID,
    p_limit int DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    title VARCHAR,
    content TEXT,
    source VARCHAR,  -- 'exam' or 'legal'
    source_type VARCHAR,
    tags TEXT[],
    is_pinned BOOLEAN,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    RETURN QUERY
    (
        SELECT
            n.id,
            n.title,
            n.content,
            'exam'::VARCHAR as source,
            n.source_type,
            n.tags,
            n.is_pinned,
            n.created_at
        FROM public.exam_note n
        WHERE n.user_id = p_user_id AND n.is_archived = false

        UNION ALL

        SELECT
            n.id,
            n.title,
            n.content,
            'legal'::VARCHAR as source,
            n.source_type,
            n.tags,
            n.is_pinned,
            n.created_at
        FROM public.legal_note n
        WHERE n.user_id = p_user_id AND n.is_archived = false
    )
    ORDER BY created_at DESC
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION public.match_exam_notes(
    p_user_id UUID,
    query_embedding vector(1536),
    match_threshold float DEFAULT 0.7,
    match_count int DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    title VARCHAR,
    content TEXT,
    source_type VARCHAR,
    source_metadata JSONB,
    tags TEXT[],
    similarity float,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    RETURN QUERY
    SELECT
        n.id,
        n.title,
        n.content,
        n.source_type,
        n.source_metadata,
        n.tags,
        1 - (ne.embedding <=> query_embedding) as similarity,
        n.created_at
    FROM public.exam_note n
    JOIN public.exam_note_embedding ne ON ne.note_id = n.id
    WHERE
        n.user_id = p_user_id
        AND n.is_archived = false
        AND 1 - (ne.embedding <=> query_embedding) > match_threshold
    ORDER BY ne.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."get_legal_notes_by_source"("p_user_id" "uuid", "p_source_type" character varying, "p_source_id" character varying DEFAULT NULL::character varying) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    RETURN COALESCE((
        SELECT json_agg(json_build_object(
            'id', n.id,
            'title', n.title,
            'content', n.content,
            'highlighted_text', n.highlighted_text,
            'tags', n.tags,
            'is_pinned', n.is_pinned,
            'source_url', n.source_url,
            'source_metadata', n.source_metadata,
            'created_at', n.created_at
        ) ORDER BY n.is_pinned DESC, n.created_at DESC)
        FROM public.legal_note n
        WHERE n.user_id = p_user_id
        AND n.source_type = p_source_type
        AND (p_source_id IS NULL OR n.source_id = p_source_id)
        AND n.is_archived = false
    ), '[]'::json);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."match_legal_notes"("p_user_id" "uuid", "query_embedding" "public"."vector", "match_threshold" double precision DEFAULT 0.7, "match_count" integer DEFAULT 10) RETURNS TABLE("id" "uuid", "title" character varying, "content" "text", "highlighted_text" "text", "source_type" character varying, "source_url" "text", "source_metadata" "jsonb", "tags" "text"[], "similarity" double precision, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    RETURN QUERY
    SELECT
        n.id,
        n.title,
        n.content,
        n.highlighted_text,
        n.source_type,
        n.source_url,
        n.source_metadata,
        n.tags,
        1 - (ne.embedding <=> query_embedding) as similarity,
        n.created_at
    FROM public.legal_note n
    JOIN public.legal_note_embedding ne ON ne.note_id = n.id
    WHERE
        n.user_id = p_user_id
        AND n.is_archived = false
        AND 1 - (ne.embedding <=> query_embedding) > match_threshold
    ORDER BY ne.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."link_local_sessions_to_user"("p_user_id" "uuid", "p_local_user_id" character varying) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count INTEGER;
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    -- Update all sessions with this local_user_id to belong to the authenticated user
    UPDATE public.conversation
    SET 
        user_id = p_user_id,
        updated_at = now()
    WHERE local_user_id = p_local_user_id
    AND user_id IS NULL;
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    
    RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_conversations(p_user_id uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
RETURNS TABLE(id uuid, external_id uuid, title character varying, source character varying, context_type character varying, model character varying, total_tokens integer, message_count bigint, synced_from_extension boolean, created_at timestamp with time zone, updated_at timestamp with time zone)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    PERFORM public.assert_caller_is(p_user_id);
    RETURN QUERY
    SELECT
        c.id,
        c.external_id,
        c.title,
        c.source,
        c.context_type,
        c.model,
        c.total_tokens,
        (SELECT COUNT(*) FROM public.conversation_message m WHERE m.conversation_id = c.id) AS message_count,
        c.synced_from_extension,
        c.created_at,
        c.updated_at
    FROM public.conversation c
    WHERE c.user_id = p_user_id
    AND c.is_deleted = false
    ORDER BY c.updated_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;


-- -----------------------------------------------------------------------------
-- Extension sync: owner checks, and no check-then-insert race
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_extension_session(
    p_user_id uuid,
    p_external_id uuid,
    p_local_user_id character varying,
    p_title character varying,
    p_source character varying DEFAULT 'precedent_extension'::character varying,
    p_context_type character varying DEFAULT NULL::character varying,
    p_context_id character varying DEFAULT NULL::character varying,
    p_context_metadata jsonb DEFAULT NULL::jsonb,
    p_model character varying DEFAULT 'gpt-4o-mini'::character varying,
    p_total_tokens integer DEFAULT 0,
    p_created_at timestamp with time zone DEFAULT now(),
    p_updated_at timestamp with time zone DEFAULT now()
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_conversation_id uuid;
BEGIN
    PERFORM public.assert_caller_is(p_user_id);

    -- Update the session if it exists and is this user's, else insert it. An
    -- insert that loses a race to a concurrent sync of the same session goes
    -- round once more and updates the row that sync created.
    FOR i IN 1..2 LOOP
        UPDATE public.conversation
        SET
            title = COALESCE(p_title, title),
            context_type = COALESCE(p_context_type, context_type),
            context_id = COALESCE(p_context_id, context_id),
            context_metadata = COALESCE(p_context_metadata, context_metadata),
            total_tokens = p_total_tokens,
            updated_at = p_updated_at,
            extension_synced_at = now()
        WHERE external_id = p_external_id AND user_id = p_user_id
        RETURNING id INTO v_conversation_id;

        IF v_conversation_id IS NOT NULL THEN
            RETURN v_conversation_id;
        END IF;

        INSERT INTO public.conversation (
            user_id, external_id, local_user_id, title, source,
            context_type, context_id, context_metadata, model,
            total_tokens, synced_from_extension, extension_synced_at,
            created_at, updated_at
        ) VALUES (
            p_user_id, p_external_id, p_local_user_id, p_title, p_source,
            p_context_type, p_context_id, p_context_metadata, p_model,
            p_total_tokens, true, now(),
            p_created_at, p_updated_at
        )
        ON CONFLICT (external_id) WHERE external_id IS NOT NULL DO NOTHING
        RETURNING id INTO v_conversation_id;

        IF v_conversation_id IS NOT NULL THEN
            RETURN v_conversation_id;
        END IF;
    END LOOP;

    -- The external id exists, but not for this user
    RAISE EXCEPTION 'Session belongs to another user' USING ERRCODE = '42501';
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_extension_message(
    p_conversation_id uuid,
    p_external_id uuid,
    p_role public.conversation_role,
    p_content text,
    p_tokens_used integer DEFAULT NULL::integer,
    p_model character varying DEFAULT NULL::character varying,
    p_metadata jsonb DEFAULT NULL::jsonb,
    p_created_at timestamp with time zone DEFAULT now()
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_owner uuid;
    v_message_id bigint;
BEGIN
    SELECT user_id INTO v_owner FROM public.conversation WHERE id = p_conversation_id;
    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'Conversation not found' USING ERRCODE = 'P0002';
    END IF;
    PERFORM public.assert_caller_is(v_owner);

    INSERT INTO public.conversation_message (
        conversation_id, external_id, role, content,
        tokens_used, model, metadata, created_at
    ) VALUES (
        p_conversation_id, p_external_id, p_role, p_content,
        p_tokens_used, p_model, p_metadata, p_created_at
    )
    ON CONFLICT (external_id) WHERE external_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_message_id;

    -- Already synced (e.g. a retried or concurrent delivery): return that message
    IF v_message_id IS NULL THEN
        SELECT id INTO v_message_id FROM public.conversation_message
        WHERE external_id = p_external_id AND conversation_id = p_conversation_id;
        IF v_message_id IS NULL THEN
            RAISE EXCEPTION 'Message belongs to another conversation' USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN v_message_id;
END;
$$;


-- -----------------------------------------------------------------------------
-- Privileges. A function gets EXECUTE for PUBLIC by default, and Supabase's
-- default privileges add anon, authenticated and service_role: revoke all of
-- that and grant back only what each one needs.
-- -----------------------------------------------------------------------------

DO $migration$
DECLARE
    f regprocedure;
BEGIN
    FOR f IN
        SELECT p.oid::regprocedure FROM pg_proc p
        WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN (
            'assert_caller_is',
            'get_unified_ai_context', 'search_all_notes', 'get_notes_summary', 'get_recent_notes',
            'match_exam_notes', 'get_legal_notes_by_source', 'match_legal_notes', 'get_user_conversations',
            'link_local_sessions_to_user', 'sync_extension_session', 'sync_extension_message',
            'upsert_exam_note_embedding', 'upsert_legal_note_embedding'
        )
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
    END LOOP;

    -- Called with the user's own JWT
    FOR f IN
        SELECT p.oid::regprocedure FROM pg_proc p
        WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN (
            'get_unified_ai_context', 'search_all_notes', 'get_notes_summary', 'get_recent_notes',
            'match_exam_notes', 'get_legal_notes_by_source', 'match_legal_notes', 'get_user_conversations',
            'link_local_sessions_to_user', 'sync_extension_session', 'sync_extension_message'
        )
    LOOP
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
    END LOOP;
END
$migration$;
