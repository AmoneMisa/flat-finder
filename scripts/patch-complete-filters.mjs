import fs from 'node:fs'

function patch(path, replacements) {
  let source = fs.readFileSync(path, 'utf8')
  for (const [label, before, after] of replacements) {
    if (!source.includes(before)) throw new Error(`${path}: target not found: ${label}`)
    source = source.replace(before, after)
  }
  fs.writeFileSync(path, source)
}

patch('backend/src/server.js', [
  ['numeric filters',
`    roomsMin: num(q.roomsMin),
    roomsMax: num(q.roomsMax),
    bedroomsMin: num(q.bedroomsMin),
    bedroomsMax: num(q.bedroomsMax),
    floorMin: num(q.floorMin),
    floorMax: num(q.floorMax),
    yearMin: num(q.yearMin),
    yearMax: num(q.yearMax),`,
`    roomsMin: num(q.roomsMin),
    roomsMax: num(q.roomsMax),
    bedroomsMin: num(q.bedroomsMin),
    bedroomsMax: num(q.bedroomsMax),
    areaMin: num(q.areaMin),
    areaMax: num(q.areaMax),
    floorMin: num(q.floorMin),
    floorMax: num(q.floorMax),
    totalFloorsMin: num(q.totalFloorsMin),
    totalFloorsMax: num(q.totalFloorsMax),
    yearMin: num(q.yearMin),
    yearMax: num(q.yearMax),
    newBuilding: bool(q.newBuilding),`],
])

patch('backend/src/normalize.js', [
  ['new building age',
`      (buildingYear && buildingYear >= new Date().getFullYear() - 3 ? true : null));`,
`      (buildingYear && buildingYear >= new Date().getFullYear() - 5 ? true : null));`],
  ['destructure filters',
`    roomsMin, roomsMax, bedroomsMin, bedroomsMax,
    floorMin, floorMax, yearMin, yearMax, audience, city,
    cityAliases, district, metro, listingId,
    pets, children, roomOnly, maxAgeDays, sources,`,
`    roomsMin, roomsMax, bedroomsMin, bedroomsMax, areaMin, areaMax,
    floorMin, floorMax, totalFloorsMin, totalFloorsMax, yearMin, yearMax,
    newBuilding, audience, city, cityAliases, district, metro, listingId,
    pets, children, roomOnly, maxAgeDays, sources,`],
  ['apply numeric filters',
`    if (bedroomsMin != null && (l.bedrooms == null || l.bedrooms < bedroomsMin)) return false;
    if (bedroomsMax != null && (l.bedrooms == null || l.bedrooms > bedroomsMax)) return false;
    if (floorMin != null && (l.floor == null || l.floor < floorMin)) return false;
    if (floorMax != null && (l.floor == null || l.floor > floorMax)) return false;
    if (yearMin != null && (l.buildingYear == null || l.buildingYear < yearMin)) return false;
    if (yearMax != null && (l.buildingYear == null || l.buildingYear > yearMax)) return false;`,
`    if (bedroomsMin != null && (l.bedrooms == null || l.bedrooms < bedroomsMin)) return false;
    if (bedroomsMax != null && (l.bedrooms == null || l.bedrooms > bedroomsMax)) return false;
    if (areaMin != null && (l.areaSqm == null || l.areaSqm < areaMin)) return false;
    if (areaMax != null && (l.areaSqm == null || l.areaSqm > areaMax)) return false;
    if (floorMin != null && (l.floor == null || l.floor < floorMin)) return false;
    if (floorMax != null && (l.floor == null || l.floor > floorMax)) return false;
    if (totalFloorsMin != null && (l.totalFloors == null || l.totalFloors < totalFloorsMin)) return false;
    if (totalFloorsMax != null && (l.totalFloors == null || l.totalFloors > totalFloorsMax)) return false;
    if (yearMin != null && (l.buildingYear == null || l.buildingYear < yearMin)) return false;
    if (yearMax != null && (l.buildingYear == null || l.buildingYear > yearMax)) return false;
    if (newBuilding === true && l.newBuilding !== true) return false;`],
])

console.log('Complete housing filter patch applied')
