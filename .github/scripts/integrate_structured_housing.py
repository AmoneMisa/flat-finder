from pathlib import Path

path = Path('backend/src/normalize.js')
text = path.read_text()

text = text.replace(
    '  parseHousingSemanticContext,\n  parseLexiconAddress,',
    '  parseHousingSemanticContext,\n  parseHousingStructuredContext,\n  parseLexiconAddress,',
    1,
)

text = text.replace(
    "  const country = parseCanonicalCountryCode(partial.country) || '';\n  const propertyType = partial.propertyType === 'house' ? 'house' : 'flat';\n  const byAgency = Boolean(partial.byAgency);\n  const rooms = partial.rooms != null ? Number(partial.rooms) : parseRoomsFromText(combined);\n  const housingIntent = parseHousingIntent(combined);\n  const housingContext = parseHousingSemanticContext(combined);",
    "  const country = parseCanonicalCountryCode(partial.country) || '';\n  const propertyType = partial.propertyType === 'house' ? 'house' : 'flat';\n  const housingStructured = parseHousingStructuredContext(combined);\n  const byAgency = partial.byAgency != null\n    ? Boolean(partial.byAgency)\n    : housingStructured.seller.type === 'agency';\n  const rooms = partial.rooms != null\n    ? Number(partial.rooms)\n    : (housingStructured.rooms ?? parseRoomsFromText(combined));\n  const housingIntent = housingStructured.intent ?? parseHousingIntent(combined);\n  const housingContext = housingStructured.context ?? parseHousingSemanticContext(combined);",
    1,
)

text = text.replace(
    "  const parsedFloor = parseFloor(combined);\n  const floor = partial.floor != null ? Number(partial.floor) : parsedFloor.floor;\n  const totalFloors = partial.totalFloors != null ? Number(partial.totalFloors) : parsedFloor.totalFloors;",
    "  const parsedFloor = parseFloor(combined);\n  const floor = partial.floor != null\n    ? Number(partial.floor)\n    : (housingStructured.floor.floor ?? parsedFloor.floor);\n  const totalFloors = partial.totalFloors != null\n    ? Number(partial.totalFloors)\n    : (housingStructured.floor.totalFloors ?? parsedFloor.totalFloors);",
    1,
)

text = text.replace(
    "  const dep = parseDeposit(combined);\n  const depositKind = partial.depositKind ?? parseDepositKind(combined);\n  const deposit = partial.deposit ?? (depositKind === 'noDeposit' ? false : dep.required);\n  const depositAmount = partial.depositAmount ?? dep.amount;\n  const depositCurrency = partial.depositCurrency ?? dep.currency ?? null;\n\n  const com = parseCommission(combined);\n  const commission = partial.commission ?? com.has;\n  const commissionPercent = partial.commissionPercent ?? com.percent;",
    "  const dep = parseDeposit(combined);\n  const structuredDeposit = housingStructured.payments.deposit;\n  const depositKind = partial.depositKind\n    ?? structuredDeposit.kind\n    ?? parseDepositKind(combined);\n  const deposit = partial.deposit\n    ?? structuredDeposit.required\n    ?? (depositKind === 'noDeposit' ? false : dep.required);\n  const depositAmount = partial.depositAmount\n    ?? structuredDeposit.amount\n    ?? dep.amount;\n  const depositCurrency = partial.depositCurrency\n    ?? structuredDeposit.currency\n    ?? dep.currency\n    ?? null;\n\n  const com = parseCommission(combined);\n  const structuredCommission = housingStructured.payments.commission;\n  const commission = partial.commission\n    ?? structuredCommission.required\n    ?? com.has;\n  const commissionPercent = partial.commissionPercent\n    ?? structuredCommission.percent\n    ?? com.percent;",
    1,
)

text = text.replace(
    "  const areaSqm = partial.areaSqm != null ? Number(partial.areaSqm) : parseAreaFromText(combined);",
    "  const areaSqm = partial.areaSqm != null\n    ? Number(partial.areaSqm)\n    : (housingStructured.area.total ?? parseAreaFromText(combined));",
    1,
)

text = text.replace(
    "    areaSqm,\n    city,",
    "    areaSqm,\n    areaDetails: partial.areaDetails ?? housingStructured.area,\n    city,",
    1,
)
text = text.replace(
    "    commissionPercent,\n    balcony,",
    "    commissionPercent,\n    paymentContext: partial.paymentContext ?? housingStructured.payments,\n    sellerType: partial.sellerType ?? housingStructured.seller.type ?? (byAgency ? 'agency' : null),\n    sellerConfidence: partial.sellerConfidence ?? housingStructured.seller.confidence,\n    infrastructure: Array.isArray(partial.infrastructure) ? partial.infrastructure : [...housingStructured.infrastructure],\n    balcony,",
    1,
)

required = [
    'parseHousingStructuredContext',
    'housingStructured.rooms',
    'housingStructured.floor.floor',
    'housingStructured.payments.deposit',
    'areaDetails:',
    'paymentContext:',
    'sellerConfidence:',
    'infrastructure:',
]
for marker in required:
    if marker not in text:
        raise SystemExit(f'missing structured housing marker: {marker}')

path.write_text(text)
