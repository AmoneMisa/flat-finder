import {
  canUseFastListingPath,
  searchPostgresListings as searchPostgresListingsCore,
} from './postgres-search-fast-core.js';
import {
  attachScopeToCursor,
  prepareCursorForScope,
  searchCursorScope,
} from './postgres-cursor-scope.js';

export {canUseFastListingPath};

export async function searchPostgresListings(args) {
  const filters = args?.filters || {};
  const scope = searchCursorScope(filters, args?.countries || []);
  const scopedFilters = {
    ...filters,
    cursor: prepareCursorForScope(filters.cursor, scope),
  };

  const result = await searchPostgresListingsCore({...args, filters: scopedFilters});
  return {
    ...result,
    nextCursor: attachScopeToCursor(result.nextCursor, scope),
  };
}
