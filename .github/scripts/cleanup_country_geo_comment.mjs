import {readFileSync, writeFileSync} from 'node:fs';
const path='backend/src/countries.js';
let source=readFileSync(path,'utf8');
source=source.replace("    // Localized forms OLX/posts actually use, so the city filter matches. The\n    // canonical (English) name is always accepted too; diacritics are ignored.\n",'');
writeFileSync(path,source);
