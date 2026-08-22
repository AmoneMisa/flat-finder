// Small dedicated parsers for amenities that need first-class boolean filters.
// Existing textparse.js keeps the broader free-form amenity list; these return
// true/null so an unstated feature never satisfies an explicit "has X" filter.

export function parseDishwasher(text) {
  if (!text) return null;
  return /(?:посудомо|посудомийн|dishwasher|idish\s*yuvish|idishyuvg|ma[șs]ina de sp[ăa]lat vase)/i.test(text)
    ? true
    : null;
}

export function parseTerrace(text) {
  if (!text) return null;
  return /(?:террас|терас|terrace|teras(?:ă|a)?|patio)/i.test(text)
    ? true
    : null;
}

export function parsePrivateYard(text) {
  if (!text) return null;
  // Deliberately require an ownership/private marker: a generic common
  // courtyard must not satisfy the "личный дворик" filter.
  return /(?:личн(?:ый|ого|ым)\s+двор|сво[йеё]\s+(?:закрыт(?:ый|ого)\s+)?двор|собственн(?:ый|ого)\s+двор|приватн(?:ий|ый)\s+двір|власн(?:ий|ого)\s+двір|private\s+(?:courtyard|yard)|curte\s+(?:proprie|privat[ăa])|o['’`]?z\s+hovli(?:si)?|shaxsiy\s+hovli)/i.test(text)
    ? true
    : null;
}
