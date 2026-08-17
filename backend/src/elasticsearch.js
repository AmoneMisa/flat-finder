import {
    Client,
} from '@elastic/elasticsearch';

import {
    getActiveListingsBatch,
} from './db.js';

const ELASTICSEARCH_URL =
    process.env.ELASTICSEARCH_URL ||
    'http://flat-finder-elasticsearch:9200';

export const SEARCH_INDEX =
    process.env.ELASTICSEARCH_INDEX ||
    'flat-listings-v1';

const client =
    new Client({
        node:
        ELASTICSEARCH_URL,

        maxRetries: 3,

        requestTimeout:
            15_000,
    });

function searchableText() {
    return {
        type: 'text',

        analyzer:
            'flat_text',

        fields: {
            latin: {
                type: 'text',
                analyzer:
                    'flat_latin',
            },
        },
    };
}

function locationText() {
    return {
        type: 'text',

        analyzer:
            'flat_text',

        fields: {
            latin: {
                type: 'text',
                analyzer:
                    'flat_latin',
            },

            raw: {
                type: 'keyword',
                normalizer:
                    'flat_keyword',
            },
        },
    };
}

function indexDefinition() {
    return {
        settings: {
            number_of_shards: 1,

            number_of_replicas: 0,

            analysis: {
                filter: {
                    flat_ascii: {
                        type:
                            'asciifolding',

                        preserve_original:
                            true,
                    },

                    flat_transliteration: {
                        type:
                            'icu_transform',

                        id:
                            'Any-Latin; ' +
                            'NFD; ' +
                            '[:Nonspacing Mark:] Remove; ' +
                            'NFC',
                    },
                },

                analyzer: {
                    /*
                     * Обычный текст:
                     *
                     * București → bucuresti
                     * CHILANZAR → chilanzar
                     */
                    flat_text: {
                        type:
                            'custom',

                        tokenizer:
                            'standard',

                        filter: [
                            'lowercase',
                            'flat_ascii',
                        ],
                    },

                    /*
                     * Транслитерированное поле:
                     *
                     * Чиланзар → cilanzar
                     * квартира → kvartira
                     */
                    flat_latin: {
                        type:
                            'custom',

                        tokenizer:
                            'standard',

                        filter: [
                            'flat_transliteration',
                            'lowercase',
                            'flat_ascii',
                        ],
                    },
                },

                normalizer: {
                    flat_keyword: {
                        type:
                            'custom',

                        filter: [
                            'lowercase',
                            'asciifolding',
                        ],
                    },
                },
            },
        },

        mappings: {
            /*
             * Новые поля Listing можно
             * хранить в _source, но они
             * автоматически не создадут
             * тысячи mappings.
             */
            dynamic: false,

            properties: {
                id: {
                    type:
                        'keyword',
                },

                source: {
                    type:
                        'keyword',
                },

                country: {
                    type:
                        'keyword',
                },

                title:
                    searchableText(),

                description:
                    searchableText(),

                propertyType: {
                    type:
                        'keyword',
                },

                dealType: {
                    type:
                        'keyword',
                },

                city:
                    locationText(),

                district:
                    locationText(),

                area:
                    locationText(),

                kvartal:
                    locationText(),

                metro:
                    locationText(),

                address:
                    locationText(),

                residenceComplex:
                    locationText(),

                nearby:
                    searchableText(),

                nearbyShops:
                    searchableText(),

                amenities:
                    searchableText(),

                tags:
                    searchableText(),

                contact:
                    searchableText(),

                price: {
                    type:
                        'double',
                },

                currency: {
                    type:
                        'keyword',
                },

                rooms: {
                    type:
                        'integer',
                },

                bedrooms: {
                    type:
                        'integer',
                },

                bathrooms: {
                    type:
                        'integer',
                },

                areaSqm: {
                    type:
                        'double',
                },

                floor: {
                    type:
                        'integer',
                },

                totalFloors: {
                    type:
                        'integer',
                },

                buildingYear: {
                    type:
                        'integer',
                },

                byAgency: {
                    type:
                        'boolean',
                },

                commercial: {
                    type:
                        'boolean',
                },

                roomOnly: {
                    type:
                        'boolean',
                },

                petsAllowed: {
                    type:
                        'boolean',
                },

                childrenAllowed: {
                    type:
                        'boolean',
                },

                furnished: {
                    type:
                        'boolean',
                },

                newBuilding: {
                    type:
                        'boolean',
                },

                balcony: {
                    type:
                        'boolean',
                },

                parking: {
                    type:
                        'boolean',
                },

                elevator: {
                    type:
                        'boolean',
                },

                airConditioner: {
                    type:
                        'boolean',
                },

                internet: {
                    type:
                        'boolean',
                },

                negotiable: {
                    type:
                        'boolean',
                },

                createdAt: {
                    type:
                        'date',
                },

                firstSeenAt: {
                    type:
                        'date',
                },

                lastSeenAt: {
                    type:
                        'date',
                },

                updatedAt: {
                    type:
                        'date',
                },

                active: {
                    type:
                        'boolean',
                },

                location: {
                    type:
                        'geo_point',
                },
            },
        },
    };
}

function documentId(listing) {
    return [
        String(
            listing.source || '',
        ).toLowerCase(),

        String(
            listing.country || '',
        ).toUpperCase(),

        String(
            listing.id,
        ),
    ].join(':');
}

function validCoordinate(value) {
    const number =
        Number(value);

    return Number.isFinite(number)
        ? number
        : null;
}

function toSearchDocument(
    listing,
    metadata = {},
) {
    const lat =
        validCoordinate(
            listing.lat,
        );

    const lng =
        validCoordinate(
            listing.lng,
        );

    const document = {
        ...listing,

        id:
            String(
                listing.id,
            ),

        source:
            String(
                listing.source || '',
            ).toLowerCase(),

        country:
            String(
                listing.country || '',
            ).toUpperCase(),

        active:
            metadata.active ??
            true,
    };

    if (
        metadata.firstSeenAt
    ) {
        document.firstSeenAt =
            metadata.firstSeenAt;
    }

    if (
        metadata.lastSeenAt
    ) {
        document.lastSeenAt =
            metadata.lastSeenAt;
    }

    if (
        metadata.updatedAt
    ) {
        document.updatedAt =
            metadata.updatedAt;
    }

    if (
        lat != null &&
        lng != null
    ) {
        document.location = {
            lat,
            lon: lng,
        };
    }

    return document;
}

export async function initElasticsearch() {
    await client.ping();

    const exists =
        await client.indices.exists({
            index:
            SEARCH_INDEX,
        });

    if (!exists) {
        await client.indices.create({
            index:
            SEARCH_INDEX,

            ...indexDefinition(),
        });

        console.log(
            `[elasticsearch] index ` +
            `${SEARCH_INDEX} created`,
        );
    }

    console.log(
        `[elasticsearch] connected ` +
        `${ELASTICSEARCH_URL}`,
    );

    return true;
}

export async function elasticsearchHealth() {
    try {
        const health =
            await client.cluster.health();

        return {
            ok: true,

            status:
            health.status,

            clusterName:
            health.cluster_name,

            nodes:
            health.number_of_nodes,
        };
    } catch (err) {
        return {
            ok: false,

            error:
                err?.message ??
                String(err),
        };
    }
}

export async function indexListings(
    listings,
) {
    if (
        !Array.isArray(listings) ||
        !listings.length
    ) {
        return 0;
    }

    const unique =
        new Map();

    for (
        const listing
        of listings
        ) {
        if (
            !listing?.source ||
            !listing?.country ||
            listing?.id == null
        ) {
            continue;
        }

        unique.set(
            documentId(
                listing,
            ),
            listing,
        );
    }

    if (!unique.size) {
        return 0;
    }

    const operations = [];

    for (
        const [
            id,
            listing,
        ]
        of unique
        ) {
        operations.push({
            index: {
                _index:
                SEARCH_INDEX,

                _id:
                id,
            },
        });

        operations.push(
            toSearchDocument(
                listing,
            ),
        );
    }

    const result =
        await client.bulk({
            operations,

            refresh: false,
        });

    if (
        result.errors
    ) {
        const failures = [];

        for (
            const item
            of result.items || []
            ) {
            const operation =
                item.index ||
                item.create ||
                item.update ||
                item.delete;

            if (
                operation?.error
            ) {
                failures.push({
                    id:
                    operation._id,

                    status:
                    operation.status,

                    error:
                    operation.error
                        ?.reason,
                });
            }

            if (
                failures.length >= 10
            ) {
                break;
            }
        }

        throw new Error(
            `Elasticsearch bulk indexing failed: ` +
            JSON.stringify(
                failures,
            ),
        );
    }

    return unique.size;
}

async function indexDbRows(
    rows,
) {
    if (
        !Array.isArray(rows) ||
        !rows.length
    ) {
        return 0;
    }

    const operations = [];

    for (const row of rows) {
        const listing = {
            ...(row.data || {}),

            id:
                String(
                    row.source_id,
                ),

            source:
            row.source,

            country:
            row.country,
        };

        operations.push({
            index: {
                _index:
                SEARCH_INDEX,

                _id:
                    documentId(
                        listing,
                    ),
            },
        });

        operations.push(
            toSearchDocument(
                listing,
                {
                    active: true,

                    firstSeenAt:
                    row.first_seen_at,

                    lastSeenAt:
                    row.last_seen_at,

                    updatedAt:
                    row.updated_at,
                },
            ),
        );
    }

    const result =
        await client.bulk({
            operations,

            refresh: false,
        });

    if (
        result.errors
    ) {
        const failed =
            (result.items || [])
                .filter(
                    (item) =>
                        item.index
                            ?.error,
                )
                .slice(0, 10)
                .map(
                    (item) => ({
                        id:
                        item.index
                            ?._id,

                        error:
                        item.index
                            ?.error
                            ?.reason,
                    }),
                );

        throw new Error(
            `Elasticsearch DB bulk failed: ` +
            JSON.stringify(
                failed,
            ),
        );
    }

    return rows.length;
}

export async function deleteListingDocuments(
    listings,
) {
    if (
        !Array.isArray(listings) ||
        !listings.length
    ) {
        return 0;
    }

    const ids =
        new Set();

    for (
        const listing
        of listings
        ) {
        if (
            !listing?.source ||
            !listing?.country ||
            listing?.id == null
        ) {
            continue;
        }

        ids.add(
            documentId(
                listing,
            ),
        );
    }

    if (!ids.size) {
        return 0;
    }

    const operations = [];

    for (const id of ids) {
        operations.push({
            delete: {
                _index:
                SEARCH_INDEX,

                _id:
                id,
            },
        });
    }

    const result =
        await client.bulk({
            operations,

            refresh: false,
        });

    const fatalErrors =
        (result.items || [])
            .map(
                (item) =>
                    item.delete,
            )
            .filter(
                (item) =>
                    item?.error &&
                    item.status !== 404,
            );

    if (fatalErrors.length) {
        throw new Error(
            `Elasticsearch delete failed: ` +
            JSON.stringify(
                fatalErrors.slice(
                    0,
                    10,
                ),
            ),
        );
    }

    return ids.size;
}

export async function rebuildSearchIndex() {
    await initElasticsearch();

    console.log(
        `[elasticsearch] rebuilding ` +
        `${SEARCH_INDEX}`,
    );

    /*
     * Индекс/его mapping оставляем,
     * удаляем только документы.
     */
    await client.deleteByQuery({
        index:
        SEARCH_INDEX,

        conflicts:
            'proceed',

        refresh:
            true,

        query: {
            match_all: {},
        },
    });

    const BATCH_SIZE =
        500;

    let afterId =
        0;

    let indexed =
        0;

    while (true) {
        const rows =
            await getActiveListingsBatch(
                afterId,
                BATCH_SIZE,
            );

        if (!rows.length) {
            break;
        }

        await indexDbRows(
            rows,
        );

        indexed +=
            rows.length;

        afterId =
            rows[
            rows.length - 1
                ].db_id;

        console.log(
            `[elasticsearch] indexed ` +
            `${indexed}`,
        );
    }

    await client.indices.refresh({
        index:
        SEARCH_INDEX,
    });

    const count =
        await client.count({
            index:
            SEARCH_INDEX,
        });

    console.log(
        `[elasticsearch] rebuild complete: ` +
        `${count.count} documents`,
    );

    return {
        indexed:
        count.count,
    };
}

export async function getElasticsearchStats() {
    const health =
        await elasticsearchHealth();

    if (!health.ok) {
        return {
            ...health,

            index:
            SEARCH_INDEX,

            documents: 0,
        };
    }

    const count =
        await client.count({
            index:
            SEARCH_INDEX,
        });

    return {
        ...health,

        index:
        SEARCH_INDEX,

        documents:
        count.count,
    };
}

export async function closeElasticsearch() {
    await client.close();
}