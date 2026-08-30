-- Avoid deleting/reinserting normalized search relations when listings.data
-- changes only in unrelated fields (publicId, propertyClusterId, anti-fake
-- metadata, etc.). INSERTs still always populate the relation tables.

DROP TRIGGER IF EXISTS listings_sync_search_relations ON listings;
DROP TRIGGER IF EXISTS listings_insert_search_relations ON listings;
DROP TRIGGER IF EXISTS listings_update_search_relations ON listings;

CREATE TRIGGER listings_insert_search_relations
AFTER INSERT ON listings
FOR EACH ROW
EXECUTE FUNCTION sync_listing_search_relations();

CREATE TRIGGER listings_update_search_relations
AFTER UPDATE OF data ON listings
FOR EACH ROW
WHEN (
  OLD.data->'microdistrict' IS DISTINCT FROM NEW.data->'microdistrict'
  OR OLD.data->'kvartal' IS DISTINCT FROM NEW.data->'kvartal'
  OR OLD.data->'area' IS DISTINCT FROM NEW.data->'area'
  OR OLD.data->'localAreas' IS DISTINCT FROM NEW.data->'localAreas'
  OR OLD.data->'developmentAreas' IS DISTINCT FROM NEW.data->'developmentAreas'
  OR OLD.data->'informalAreas' IS DISTINCT FROM NEW.data->'informalAreas'
  OR OLD.data->'locationEntities' IS DISTINCT FROM NEW.data->'locationEntities'
  OR OLD.data->'nearbyPlaces' IS DISTINCT FROM NEW.data->'nearbyPlaces'
)
EXECUTE FUNCTION sync_listing_search_relations();
