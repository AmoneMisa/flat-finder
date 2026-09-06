import 'saved_listing_store_prefs.dart'
    if (dart.library.io) 'saved_listing_store_sqlite.dart' as backend;
import 'saved_listing_store_types.dart';

export 'saved_listing_store_types.dart';

/// One storage instance for the process, mirroring the shared ApiService
/// pattern. Native builds keep one SQLite connection; web/unsupported desktop
/// builds keep one normalized SharedPreferences fallback.
final SavedListingStore sharedSavedListingStore = backend.createSavedListingStore();
