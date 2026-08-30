-- Merge property-cluster membership in one database transaction. Advisory
-- transaction locks are acquired in deterministic order for every participating
-- member and existing cluster, so overlapping merges across service replicas
-- serialize without a process-local mutex or deadlock-prone lock order.

CREATE OR REPLACE FUNCTION merge_listing_property_cluster(
  p_members JSONB,
  p_proposed_cluster_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_key TEXT;
  v_existing_ids TEXT[];
  v_cluster_id TEXT;
  v_size INTEGER;
  v_members JSONB;
BEGIN
  IF p_members IS NULL
     OR jsonb_typeof(p_members) <> 'array'
     OR jsonb_array_length(p_members) = 0
  THEN
    RETURN NULL;
  END IF;

  -- Any two overlapping merge requests share at least one member lock. Sort
  -- lock acquisition globally so requests with multiple shared members cannot
  -- deadlock each other.
  FOR v_key IN
    SELECT member_key
    FROM (
      SELECT DISTINCT CONCAT_WS(':',
        LOWER(BTRIM(member.source)),
        UPPER(BTRIM(member.country)),
        BTRIM(member.source_id)
      ) AS member_key
      FROM jsonb_to_recordset(p_members)
        AS member(source TEXT, country TEXT, source_id TEXT)
      WHERE NULLIF(BTRIM(member.source), '') IS NOT NULL
        AND NULLIF(BTRIM(member.country), '') IS NOT NULL
        AND NULLIF(BTRIM(member.source_id), '') IS NOT NULL
    ) keys
    ORDER BY member_key
  LOOP
    PERFORM pg_advisory_xact_lock(
      hashtextextended('property-member:' || v_key, 0)
    );
  END LOOP;

  SELECT ARRAY_AGG(DISTINCT cluster.cluster_id ORDER BY cluster.cluster_id)
  INTO v_existing_ids
  FROM listing_property_clusters cluster
  JOIN jsonb_to_recordset(p_members)
    AS member(source TEXT, country TEXT, source_id TEXT)
    ON cluster.source = LOWER(BTRIM(member.source))
   AND cluster.country = UPPER(BTRIM(member.country))
   AND cluster.source_id = BTRIM(member.source_id);

  -- Serialize merges that touch different members of the same already-known
  -- clusters, then re-read cluster ids after waiting so the decision is based
  -- on the latest committed state.
  IF COALESCE(array_length(v_existing_ids, 1), 0) > 0 THEN
    FOREACH v_key IN ARRAY v_existing_ids
    LOOP
      PERFORM pg_advisory_xact_lock(
        hashtextextended('property-cluster:' || v_key, 0)
      );
    END LOOP;

    SELECT ARRAY_AGG(DISTINCT cluster.cluster_id ORDER BY cluster.cluster_id)
    INTO v_existing_ids
    FROM listing_property_clusters cluster
    JOIN jsonb_to_recordset(p_members)
      AS member(source TEXT, country TEXT, source_id TEXT)
      ON cluster.source = LOWER(BTRIM(member.source))
     AND cluster.country = UPPER(BTRIM(member.country))
     AND cluster.source_id = BTRIM(member.source_id);
  END IF;

  v_cluster_id := CASE
    WHEN COALESCE(array_length(v_existing_ids, 1), 0) > 0
      THEN v_existing_ids[1]
    WHEN NULLIF(BTRIM(p_proposed_cluster_id), '') IS NOT NULL
      THEN BTRIM(p_proposed_cluster_id)
    ELSE NULL
  END;

  IF v_cluster_id IS NULL THEN
    SELECT 'property:' || SUBSTRING(MD5(STRING_AGG(member_key, '|' ORDER BY member_key)) FROM 1 FOR 20)
    INTO v_cluster_id
    FROM (
      SELECT DISTINCT CONCAT_WS(':',
        LOWER(BTRIM(member.source)),
        UPPER(BTRIM(member.country)),
        BTRIM(member.source_id)
      ) AS member_key
      FROM jsonb_to_recordset(p_members)
        AS member(source TEXT, country TEXT, source_id TEXT)
      WHERE NULLIF(BTRIM(member.source), '') IS NOT NULL
        AND NULLIF(BTRIM(member.country), '') IS NOT NULL
        AND NULLIF(BTRIM(member.source_id), '') IS NOT NULL
    ) keys;
  END IF;

  IF COALESCE(array_length(v_existing_ids, 1), 0) > 1 THEN
    UPDATE listing_property_clusters
    SET cluster_id = v_cluster_id,
        last_seen_at = NOW()
    WHERE cluster_id = ANY(v_existing_ids)
      AND cluster_id <> v_cluster_id;
  END IF;

  INSERT INTO listing_property_clusters(source, country, source_id, cluster_id)
  SELECT DISTINCT
    LOWER(BTRIM(member.source)),
    UPPER(BTRIM(member.country)),
    BTRIM(member.source_id),
    v_cluster_id
  FROM jsonb_to_recordset(p_members)
    AS member(source TEXT, country TEXT, source_id TEXT)
  WHERE NULLIF(BTRIM(member.source), '') IS NOT NULL
    AND NULLIF(BTRIM(member.country), '') IS NOT NULL
    AND NULLIF(BTRIM(member.source_id), '') IS NOT NULL
  ON CONFLICT (source, country, source_id)
  DO UPDATE SET
    cluster_id = EXCLUDED.cluster_id,
    last_seen_at = NOW();

  SELECT COUNT(*)::integer
  INTO v_size
  FROM listing_property_clusters
  WHERE cluster_id = v_cluster_id;

  SELECT COALESCE(
    JSONB_AGG(
      JSONB_BUILD_OBJECT(
        'source', members.source,
        'country', members.country,
        'id', members.source_id
      )
      ORDER BY members.first_joined_at, members.source, members.country, members.source_id
    ),
    '[]'::jsonb
  )
  INTO v_members
  FROM (
    SELECT source, country, source_id, first_joined_at
    FROM listing_property_clusters
    WHERE cluster_id = v_cluster_id
    ORDER BY first_joined_at, source, country, source_id
    LIMIT 50
  ) members;

  RETURN JSONB_BUILD_OBJECT(
    'id', v_cluster_id,
    'size', COALESCE(v_size, 0),
    'members', v_members
  );
END;
$$;
