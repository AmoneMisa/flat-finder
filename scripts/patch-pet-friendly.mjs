import fs from 'node:fs'
const path = 'backend/src/normalize.js'
let source = fs.readFileSync(path, 'utf8')
const before = `    // Tenant conditions: only drop on an explicit contradiction. A listing that\n    // does not state a policy (null) is kept, like the lenient numeric ranges.\n    if (pets === true && l.petsAllowed === false) return false;`
const after = `    // Pet-friendly is an explicit positive filter: unknown policy is not enough.\n    // When requested, only listings that explicitly allow pets are returned.\n    if (pets === true && l.petsAllowed !== true) return false;`
if (!source.includes(before)) throw new Error('pet filter patch target not found')
fs.writeFileSync(path, source.replace(before, after))
