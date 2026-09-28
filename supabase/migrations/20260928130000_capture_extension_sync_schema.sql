-- Migration: capture extension-sync schema that exists in production
-- =============================================================================
-- These objects were created directly on the hosted project (for the Precedent
-- Chrome extension sync) without a migration, so a database built from this
-- repo was missing them: `supabase db reset` produced a schema that production
-- data could not be loaded into (conversation.source etc. did not exist), and
-- get_unified_ai_context() referenced a legal_note table that was never created.
--
-- Everything below is copied from the production schema and written to be
-- idempotent (IF NOT EXISTS / CREATE OR REPLACE / guarded constraints), so
-- pushing it to production is a no-op there.
--
-- SECURITY NOTE — kept as-is to mirror production, needs a follow-up:
-- the seven functions below are SECURITY DEFINER, take the target user as a
-- p_user_id argument instead of using auth.uid(), and still carry PostgreSQL's
-- default EXECUTE grant to PUBLIC (which includes the anon role). That means
-- any caller can read or write another user's conversations and legal notes
-- through /rest/v1/rpc. Fixed by the next migration,
-- 20260928130100_secure_note_and_extension_rpcs.sql.

-- conversation_role gains a system role
ALTER TYPE "public"."conversation_role" ADD VALUE IF NOT EXISTS 'system';


-- conversation: extension sync columns
ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "source" character varying(50) DEFAULT 'exam_question_bank'::character varying;

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "external_id" "uuid";

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "local_user_id" character varying(255);

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "context_type" character varying(50);

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "context_id" character varying(255);

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "context_metadata" "jsonb";

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "model" character varying(100) DEFAULT 'gpt-4o-mini'::character varying;

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "total_tokens" integer DEFAULT 0;

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "synced_from_extension" boolean DEFAULT false;

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "extension_synced_at" timestamp with time zone;

ALTER TABLE "public"."conversation" ADD COLUMN IF NOT EXISTS "is_deleted" boolean DEFAULT false;


-- conversation_message: extension sync columns
ALTER TABLE "public"."conversation_message" ADD COLUMN IF NOT EXISTS "tokens_used" integer;

ALTER TABLE "public"."conversation_message" ADD COLUMN IF NOT EXISTS "model" character varying(100);

ALTER TABLE "public"."conversation_message" ADD COLUMN IF NOT EXISTS "metadata" "jsonb";

ALTER TABLE "public"."conversation_message" ADD COLUMN IF NOT EXISTS "external_id" "uuid";


-- Legal notes (from the Precedent extension)
CREATE TABLE IF NOT EXISTS "public"."legal_note" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" character varying(255),
    "content" "text" NOT NULL,
    "content_html" "text",
    "source_type" character varying(50),
    "source_id" character varying(255),
    "source_url" "text",
    "source_metadata" "jsonb",
    "highlighted_text" "text",
    "tags" "text"[],
    "is_pinned" boolean DEFAULT false,
    "is_archived" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE "public"."legal_note" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."legal_note_embedding" (
    "note_id" "uuid" NOT NULL,
    "embedding" "public"."vector"(1536),
    "model" character varying(50) DEFAULT 'text-embedding-3-small'::character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."legal_note_embedding" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."legal_note_flashcard" (
    "id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "note_id" "uuid" NOT NULL,
    "front" "text" NOT NULL,
    "back" "text" NOT NULL,
    "ease_factor" real DEFAULT 2.5 NOT NULL,
    "interval_days" smallint DEFAULT 1 NOT NULL,
    "repetition" smallint DEFAULT 0 NOT NULL,
    "status" character varying(20) DEFAULT 'new'::character varying NOT NULL,
    "next_review_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "last_reviewed_at" timestamp with time zone,
    "review_count" smallint DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "legal_note_flashcard_status_check" CHECK ((("status")::"text" = ANY ((ARRAY['new'::character varying, 'learning'::character varying, 'review'::character varying, 'mastered'::character varying])::"text"[])))
);

ALTER TABLE "public"."legal_note_flashcard" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."legal_note_flashcard_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE "public"."legal_note_flashcard_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."legal_note_flashcard_id_seq" OWNED BY "public"."legal_note_flashcard"."id";

ALTER TABLE ONLY "public"."legal_note_flashcard" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."legal_note_flashcard_id_seq"'::"regclass");

DO $migration$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'legal_note_embedding_pkey' AND conrelid = 'public.legal_note_embedding'::regclass) THEN
    ALTER TABLE ONLY "public"."legal_note_embedding"
        ADD CONSTRAINT "legal_note_embedding_pkey" PRIMARY KEY ("note_id");
  END IF;
END
$migration$;

DO $migration$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'legal_note_flashcard_pkey' AND conrelid = 'public.legal_note_flashcard'::regclass) THEN
    ALTER TABLE ONLY "public"."legal_note_flashcard"
        ADD CONSTRAINT "legal_note_flashcard_pkey" PRIMARY KEY ("id");
  END IF;
END
$migration$;

DO $migration$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'legal_note_pkey' AND conrelid = 'public.legal_note'::regclass) THEN
    ALTER TABLE ONLY "public"."legal_note"
        ADD CONSTRAINT "legal_note_pkey" PRIMARY KEY ("id");
  END IF;
END
$migration$;

CREATE INDEX IF NOT EXISTS "idx_legal_note_created" ON "public"."legal_note" USING "btree" ("user_id", "created_at" DESC);

CREATE INDEX IF NOT EXISTS "idx_legal_note_embedding_vector" ON "public"."legal_note_embedding" USING "hnsw" ("embedding" "public"."vector_cosine_ops");

CREATE INDEX IF NOT EXISTS "idx_legal_note_flashcard_due" ON "public"."legal_note_flashcard" USING "btree" ("user_id", "next_review_date");

CREATE INDEX IF NOT EXISTS "idx_legal_note_flashcard_note" ON "public"."legal_note_flashcard" USING "btree" ("note_id");

CREATE INDEX IF NOT EXISTS "idx_legal_note_flashcard_user" ON "public"."legal_note_flashcard" USING "btree" ("user_id");

CREATE INDEX IF NOT EXISTS "idx_legal_note_fts" ON "public"."legal_note" USING "gin" ("to_tsvector"('"simple"'::"regconfig", (((((COALESCE("title", ''::character varying))::"text" || ' '::"text") || COALESCE("highlighted_text", ''::"text")) || ' '::"text") || "content")));

CREATE INDEX IF NOT EXISTS "idx_legal_note_source" ON "public"."legal_note" USING "btree" ("source_type", "source_id");

CREATE INDEX IF NOT EXISTS "idx_legal_note_tags" ON "public"."legal_note" USING "gin" ("tags");

CREATE INDEX IF NOT EXISTS "idx_legal_note_url" ON "public"."legal_note" USING "btree" ("source_url") WHERE ("source_url" IS NOT NULL);

CREATE INDEX IF NOT EXISTS "idx_legal_note_user" ON "public"."legal_note" USING "btree" ("user_id");

CREATE OR REPLACE TRIGGER "set_legal_note_updated_at" BEFORE UPDATE ON "public"."legal_note" FOR EACH ROW EXECUTE FUNCTION "public"."handle_updated_at"();

DO $migration$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'legal_note_embedding_note_id_fkey' AND conrelid = 'public.legal_note_embedding'::regclass) THEN
    ALTER TABLE ONLY "public"."legal_note_embedding"
        ADD CONSTRAINT "legal_note_embedding_note_id_fkey" FOREIGN KEY ("note_id") REFERENCES "public"."legal_note"("id") ON DELETE CASCADE;
  END IF;
END
$migration$;

DO $migration$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'legal_note_flashcard_note_id_fkey' AND conrelid = 'public.legal_note_flashcard'::regclass) THEN
    ALTER TABLE ONLY "public"."legal_note_flashcard"
        ADD CONSTRAINT "legal_note_flashcard_note_id_fkey" FOREIGN KEY ("note_id") REFERENCES "public"."legal_note"("id") ON DELETE CASCADE;
  END IF;
END
$migration$;

DO $migration$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'legal_note_flashcard_user_id_fkey' AND conrelid = 'public.legal_note_flashcard'::regclass) THEN
    ALTER TABLE ONLY "public"."legal_note_flashcard"
        ADD CONSTRAINT "legal_note_flashcard_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
  END IF;
END
$migration$;

DO $migration$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'legal_note_user_id_fkey' AND conrelid = 'public.legal_note'::regclass) THEN
    ALTER TABLE ONLY "public"."legal_note"
        ADD CONSTRAINT "legal_note_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
  END IF;
END
$migration$;

DROP POLICY IF EXISTS "Service role manages embeddings" ON "public"."legal_note_embedding";
CREATE POLICY "Service role manages embeddings" ON "public"."legal_note_embedding" TO "service_role" USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Users manage own legal note flashcards" ON "public"."legal_note_flashcard";
CREATE POLICY "Users manage own legal note flashcards" ON "public"."legal_note_flashcard" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users manage own legal notes" ON "public"."legal_note";
CREATE POLICY "Users manage own legal notes" ON "public"."legal_note" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));

DROP POLICY IF EXISTS "Users read own legal note embeddings" ON "public"."legal_note_embedding";
CREATE POLICY "Users read own legal note embeddings" ON "public"."legal_note_embedding" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."legal_note"
  WHERE (("legal_note"."id" = "legal_note_embedding"."note_id") AND ("legal_note"."user_id" = "auth"."uid"())))));

ALTER TABLE "public"."legal_note" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."legal_note_embedding" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."legal_note_flashcard" ENABLE ROW LEVEL SECURITY;


-- Indexes for extension sync
CREATE UNIQUE INDEX IF NOT EXISTS "idx_conv_external_id" ON "public"."conversation" USING "btree" ("external_id") WHERE ("external_id" IS NOT NULL);

CREATE INDEX IF NOT EXISTS "idx_conv_local_user" ON "public"."conversation" USING "btree" ("local_user_id") WHERE ("local_user_id" IS NOT NULL);

CREATE INDEX IF NOT EXISTS "idx_conv_source" ON "public"."conversation" USING "btree" ("source");

CREATE UNIQUE INDEX IF NOT EXISTS "idx_msg_external_id" ON "public"."conversation_message" USING "btree" ("external_id") WHERE ("external_id" IS NOT NULL);


-- Column comments
COMMENT ON COLUMN "public"."conversation"."source" IS 'Where the conversation originated: exam_question_bank, precedent_extension';

COMMENT ON COLUMN "public"."conversation"."external_id" IS 'Links to ai_chat_sessions.id in Precedent MS SQL database';

COMMENT ON COLUMN "public"."conversation"."local_user_id" IS 'Anonymous user ID from extension, used for linking after OAuth';

COMMENT ON COLUMN "public"."conversation"."synced_from_extension" IS 'True if this conversation was synced from Precedent extension';

COMMENT ON COLUMN "public"."conversation_message"."external_id" IS 'Links to ai_chat_messages.id in Precedent MS SQL database';


-- Functions
CREATE OR REPLACE FUNCTION "public"."get_legal_notes_by_source"("p_user_id" "uuid", "p_source_type" character varying, "p_source_id" character varying DEFAULT NULL::character varying) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
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

ALTER FUNCTION "public"."get_legal_notes_by_source"("p_user_id" "uuid", "p_source_type" character varying, "p_source_id" character varying) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_user_conversations"("p_user_id" "uuid", "p_limit" integer DEFAULT 50, "p_offset" integer DEFAULT 0) RETURNS TABLE("id" "uuid", "external_id" "uuid", "title" character varying, "source" character varying, "context_type" character varying, "model" character varying, "total_tokens" integer, "message_count" bigint, "synced_from_extension" boolean, "created_at" timestamp with time zone, "updated_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
    SELECT 
        c.id,
        c.external_id,
        c.title,
        c.source,
        c.context_type,
        c.model,
        c.total_tokens,
        (SELECT COUNT(*) FROM public.conversation_message WHERE conversation_id = c.id) as message_count,
        c.synced_from_extension,
        c.created_at,
        c.updated_at
    FROM public.conversation c
    WHERE c.user_id = p_user_id
    AND c.is_deleted = false
    ORDER BY c.updated_at DESC
    LIMIT p_limit
    OFFSET p_offset;
$$;

ALTER FUNCTION "public"."get_user_conversations"("p_user_id" "uuid", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."get_user_conversations"("p_user_id" "uuid", "p_limit" integer, "p_offset" integer) IS 'Get paginated list of user conversations with message counts';

CREATE OR REPLACE FUNCTION "public"."link_local_sessions_to_user"("p_user_id" "uuid", "p_local_user_id" character varying) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_count INTEGER;
BEGIN
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

ALTER FUNCTION "public"."link_local_sessions_to_user"("p_user_id" "uuid", "p_local_user_id" character varying) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."link_local_sessions_to_user"("p_user_id" "uuid", "p_local_user_id" character varying) IS 'Link anonymous extension sessions to authenticated user after OAuth';

CREATE OR REPLACE FUNCTION "public"."match_legal_notes"("p_user_id" "uuid", "query_embedding" "public"."vector", "match_threshold" double precision DEFAULT 0.7, "match_count" integer DEFAULT 10) RETURNS TABLE("id" "uuid", "title" character varying, "content" "text", "highlighted_text" "text", "source_type" character varying, "source_url" "text", "source_metadata" "jsonb", "tags" "text"[], "similarity" double precision, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
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

ALTER FUNCTION "public"."match_legal_notes"("p_user_id" "uuid", "query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."sync_extension_message"("p_conversation_id" "uuid", "p_external_id" "uuid", "p_role" "public"."conversation_role", "p_content" "text", "p_tokens_used" integer DEFAULT NULL::integer, "p_model" character varying DEFAULT NULL::character varying, "p_metadata" "jsonb" DEFAULT NULL::"jsonb", "p_created_at" timestamp with time zone DEFAULT "now"()) RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_message_id BIGINT;
BEGIN
    -- Check if message already exists by external_id
    SELECT id INTO v_message_id
    FROM public.conversation_message
    WHERE external_id = p_external_id;
    
    IF v_message_id IS NOT NULL THEN
        -- Message already synced, return existing ID
        RETURN v_message_id;
    END IF;
    
    -- Insert new message
    INSERT INTO public.conversation_message (
        conversation_id, external_id, role, content,
        tokens_used, model, metadata, created_at
    ) VALUES (
        p_conversation_id, p_external_id, p_role, p_content,
        p_tokens_used, p_model, p_metadata, p_created_at
    )
    RETURNING id INTO v_message_id;
    
    RETURN v_message_id;
END;
$$;

ALTER FUNCTION "public"."sync_extension_message"("p_conversation_id" "uuid", "p_external_id" "uuid", "p_role" "public"."conversation_role", "p_content" "text", "p_tokens_used" integer, "p_model" character varying, "p_metadata" "jsonb", "p_created_at" timestamp with time zone) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."sync_extension_message"("p_conversation_id" "uuid", "p_external_id" "uuid", "p_role" "public"."conversation_role", "p_content" "text", "p_tokens_used" integer, "p_model" character varying, "p_metadata" "jsonb", "p_created_at" timestamp with time zone) IS 'Insert a message synced from Precedent extension';

CREATE OR REPLACE FUNCTION "public"."sync_extension_session"("p_user_id" "uuid", "p_external_id" "uuid", "p_local_user_id" character varying, "p_title" character varying, "p_source" character varying DEFAULT 'precedent_extension'::character varying, "p_context_type" character varying DEFAULT NULL::character varying, "p_context_id" character varying DEFAULT NULL::character varying, "p_context_metadata" "jsonb" DEFAULT NULL::"jsonb", "p_model" character varying DEFAULT 'gpt-4o-mini'::character varying, "p_total_tokens" integer DEFAULT 0, "p_created_at" timestamp with time zone DEFAULT "now"(), "p_updated_at" timestamp with time zone DEFAULT "now"()) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_conversation_id UUID;
BEGIN
    -- Check if session already exists by external_id
    SELECT id INTO v_conversation_id
    FROM public.conversation
    WHERE external_id = p_external_id;
    
    IF v_conversation_id IS NOT NULL THEN
        -- Update existing session
        UPDATE public.conversation
        SET
            title = COALESCE(p_title, title),
            context_type = COALESCE(p_context_type, context_type),
            context_id = COALESCE(p_context_id, context_id),
            context_metadata = COALESCE(p_context_metadata, context_metadata),
            total_tokens = p_total_tokens,
            updated_at = p_updated_at,
            extension_synced_at = now()
        WHERE id = v_conversation_id;
    ELSE
        -- Insert new session
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
        RETURNING id INTO v_conversation_id;
    END IF;
    
    RETURN v_conversation_id;
END;
$$;

ALTER FUNCTION "public"."sync_extension_session"("p_user_id" "uuid", "p_external_id" "uuid", "p_local_user_id" character varying, "p_title" character varying, "p_source" character varying, "p_context_type" character varying, "p_context_id" character varying, "p_context_metadata" "jsonb", "p_model" character varying, "p_total_tokens" integer, "p_created_at" timestamp with time zone, "p_updated_at" timestamp with time zone) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."sync_extension_session"("p_user_id" "uuid", "p_external_id" "uuid", "p_local_user_id" character varying, "p_title" character varying, "p_source" character varying, "p_context_type" character varying, "p_context_id" character varying, "p_context_metadata" "jsonb", "p_model" character varying, "p_total_tokens" integer, "p_created_at" timestamp with time zone, "p_updated_at" timestamp with time zone) IS 'Upsert a conversation session synced from Precedent extension';

CREATE OR REPLACE FUNCTION "public"."upsert_legal_note_embedding"("p_note_id" "uuid", "p_embedding" "public"."vector", "p_model" character varying DEFAULT 'text-embedding-3-small'::character varying) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    INSERT INTO public.legal_note_embedding (note_id, embedding, model)
    VALUES (p_note_id, p_embedding, p_model)
    ON CONFLICT (note_id)
    DO UPDATE SET
        embedding = EXCLUDED.embedding,
        model = EXCLUDED.model,
        created_at = now();

    RETURN true;
END;
$$;

ALTER FUNCTION "public"."upsert_legal_note_embedding"("p_note_id" "uuid", "p_embedding" "public"."vector", "p_model" character varying) OWNER TO "postgres";


-- Grants
GRANT ALL ON FUNCTION "public"."get_legal_notes_by_source"("p_user_id" "uuid", "p_source_type" character varying, "p_source_id" character varying) TO "authenticated";

GRANT ALL ON FUNCTION "public"."get_user_conversations"("p_user_id" "uuid", "p_limit" integer, "p_offset" integer) TO "authenticated";

GRANT ALL ON FUNCTION "public"."link_local_sessions_to_user"("p_user_id" "uuid", "p_local_user_id" character varying) TO "authenticated";

GRANT ALL ON FUNCTION "public"."match_legal_notes"("p_user_id" "uuid", "query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "authenticated";

GRANT ALL ON FUNCTION "public"."sync_extension_message"("p_conversation_id" "uuid", "p_external_id" "uuid", "p_role" "public"."conversation_role", "p_content" "text", "p_tokens_used" integer, "p_model" character varying, "p_metadata" "jsonb", "p_created_at" timestamp with time zone) TO "authenticated";

GRANT ALL ON FUNCTION "public"."sync_extension_session"("p_user_id" "uuid", "p_external_id" "uuid", "p_local_user_id" character varying, "p_title" character varying, "p_source" character varying, "p_context_type" character varying, "p_context_id" character varying, "p_context_metadata" "jsonb", "p_model" character varying, "p_total_tokens" integer, "p_created_at" timestamp with time zone, "p_updated_at" timestamp with time zone) TO "authenticated";

GRANT ALL ON FUNCTION "public"."upsert_legal_note_embedding"("p_note_id" "uuid", "p_embedding" "public"."vector", "p_model" character varying) TO "service_role";

GRANT SELECT ON TABLE "public"."legal_note" TO "anon";

GRANT ALL ON TABLE "public"."legal_note" TO "authenticated";

GRANT ALL ON TABLE "public"."legal_note" TO "service_role";

GRANT SELECT ON TABLE "public"."legal_note_embedding" TO "anon";

GRANT ALL ON TABLE "public"."legal_note_embedding" TO "authenticated";

GRANT ALL ON TABLE "public"."legal_note_embedding" TO "service_role";

GRANT SELECT ON TABLE "public"."legal_note_flashcard" TO "anon";

GRANT ALL ON TABLE "public"."legal_note_flashcard" TO "authenticated";

GRANT ALL ON TABLE "public"."legal_note_flashcard" TO "service_role";

GRANT ALL ON SEQUENCE "public"."legal_note_flashcard_id_seq" TO "anon";

GRANT ALL ON SEQUENCE "public"."legal_note_flashcard_id_seq" TO "authenticated";

GRANT ALL ON SEQUENCE "public"."legal_note_flashcard_id_seq" TO "service_role";
