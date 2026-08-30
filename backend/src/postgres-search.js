import {
  buildSearchContext,
  searchPostgresListings as searchPostgresListingsCore,
} from './postgres-search-core.js';
import {
  attachScopeToCursor,
  prepareCursorForScope,
  searchCursorScope,
} from './postgres-cursor-scope.js';

export {buildSearchContext};

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
