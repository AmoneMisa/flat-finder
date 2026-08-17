
import {
    closeDb,
    initDb,
} from './db.js';

import {
    closeElasticsearch,
    initElasticsearch,
    rebuildSearchIndex,
} from './elasticsearch.js';

async function main() {
    try {
        await initDb();

        await initElasticsearch();

        const result =
            await rebuildSearchIndex();

        console.log(
            '[reindex] done:',
            result,
        );
    } finally {
        await Promise.allSettled([
            closeElasticsearch(),
            closeDb(),
        ]);
    }
}

main()
    .then(() => {
        process.exit(0);
    })
    .catch((err) => {
        console.error(
            '[reindex] failed:',
            err,
        );

        process.exit(1);
    });