import { pool } from './db.js';

function commissionPercent(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

export function isAgencyLikeListing(listing) {
  return Boolean(
    listing?.byAgency === true ||
    listing?.commission === true ||
    (commissionPercent(listing?.commissionPercent) ?? 0) > 0
  );
}

/**
 * Keep the persisted agency flag aligned with the semantic data we already
 * extract from listing text. An advert that explicitly charges a commission is
 * intermediary inventory even when a source account is not marked as business.
 *
 * The trigger protects every future upsert, while the UPDATE fixes existing
 * rows immediately on worker startup.
 */
export async function ensureListingSemantics() {
  await pool.query(`
    CREATE OR REPLACE FUNCTION enforce_listing_agency_semantics()
    RETURNS trigger AS $$
    BEGIN
      IF NEW.data @> '{"commission":true}'::jsonb
         OR (
           jsonb_typeof(NEW.data->'commissionPercent') = 'number'
           AND (NEW.data->>'commissionPercent')::numeric > 0
         )
      THEN
        NEW.by_agency := TRUE;
        NEW.data := jsonb_set(
          COALESCE(NEW.data, '{}'::jsonb),
          '{byAgency}',
          'true'::jsonb,
          TRUE
        );
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS listings_agency_semantics_trigger ON listings;
    CREATE TRIGGER listings_agency_semantics_trigger
      BEFORE INSERT OR UPDATE OF data, by_agency
      ON listings
      FOR EACH ROW
      EXECUTE FUNCTION enforce_listing_agency_semantics();

    UPDATE listings
    SET
      by_agency = TRUE,
      data = jsonb_set(
        COALESCE(data, '{}'::jsonb),
        '{byAgency}',
        'true'::jsonb,
        TRUE
      ),
      updated_at = NOW()
    WHERE by_agency = FALSE
      AND (
        data @> '{"commission":true}'::jsonb
        OR (
          jsonb_typeof(data->'commissionPercent') = 'number'
          AND (data->>'commissionPercent')::numeric > 0
        )
      );
  `);

  console.log('[listing-semantics] commission listings classified as agency');
}
