// Telegram adapter. Public Telegram *channels* are read through the MTProto
// sidecar worker (see telegram-worker/), which logs in as a real user account
// and calls messages.getHistory. This replaced scraping https://t.me/s/<channel>
// because Telegram heavily throttles that web preview from datacenter IPs (a
// production server saw ~1 post where a browser sees hundreds). The worker is
// transport-only: it returns raw message text/date, and all the housing
// parsing/filtering below stays here so there's a single source of truth.

import {makeListing} from '../normalize.js';
import {MAX_AGE_MS} from '../listing-policy.js';
import {looksTelegramRoomShare} from '../telegram-room-share.js';
import {
  parsePriceFromText,
  parseRoomsFromText,
  parseAreaFromText,
  guessPropertyType,
  classifyAgency,
  looksHousingWanted,
} from '../textparse.js';

// Base URL of the MTProto worker (set in docker-compose). When unset the
// telegram source simply yields nothing, so the backend is not hard-coupled to
// the worker being up — OLX and the other sources still return results.
const TG_WORKER_URL = process.env.TG_WORKER_URL || '';

// Only keep messages that look like housing posts. Covers RU/UA/RO plus Uzbek
// (uy/kvartira/xona/ijara) and Kazakh (пәтер/үй/жалға).
const HOUSING_RE =
  /(apartament|casa|квартир|kvartira|\bkv\b|дом|\buy|будин|пәтер|үй|кімнат|комнат|xona|ijara|arenda|аренд|жал[гғ]а|m2|м2|кв\.?\s?м|\$|€|грн|сум|so'?m|тенге|у\.?е)/i;

// Turn one worker message ({ id, text, date, hasPhoto }) into a listing, or
// null if it isn't a housing post. Search filters are applied to the complete
// normalized snapshot in server.js, just like the vacancy feed.
function messageToListing(
    msg,
    channelConfig,
    country,
) {
  const channel =
      channelConfig.name;

  const text =
      (msg.text || '')
          .replace(/[ \t]+/g, ' ')
          .trim();
  /*
   * Flat Finder показывает предложения жилья,
   * а не объявления людей, которые ищут
   * целую квартиру/дом.
   *
   * "Ищу на подселение" здесь НЕ отсекается,
   * потому что looksHousingWanted()
   * специально оставляет room/shared posts.
   */
  if (looksHousingWanted(text)) {
    return null;
  }

  if (text.length < 10) {
    return null;
  }

  if (!HOUSING_RE.test(text)) {
    return null;
  }

  const {
    price,
    currency,
  } =
      parsePriceFromText(
          text,
          country.currency,
      );

  const type =
      guessPropertyType(
          text,
      );

  const title =
      text
          .split('\n')[0]
          .slice(0, 90);

  const postPath =
      `${channel}/${msg.id}`;

  const photoIds =
      Array.isArray(
          msg.photoIds,
      ) &&
      msg.photoIds.length
          ? msg.photoIds
          : msg.hasPhoto
              ? [msg.id]
              : [];

  const photos =
      photoIds.map(
          (pid) =>
              `/api/tg-photo/${channel}/${pid}`,
      );

  return makeListing({
    id:
        `tg-${channel}-${postPath}`,

    source:
        'telegram',

    country:
    country.code,

    title,

    description:
    text,

    propertyType:
    type,

    // Uzbek rental channels often advertise a place in an existing flat as
    // "qizlarga joy bor" / "қизларга жой бор" without saying "room". That is
    // a room/share offer, not a whole apartment. Keep the generic normalizer as
    // the fallback for all other languages and wording.
    roomOnly:
        looksTelegramRoomShare(text)
            ? true
            : undefined,

    byAgency:
        classifyAgency(
            text,
        ),

    price,

    currency,

    rooms:
        parseRoomsFromText(
            text,
        ),

    areaSqm:
        parseAreaFromText(
            text,
        ),

    /*
     * Самое важное изменение:
     * город известен уже из конфигурации
     * Telegram-канала.
     *
     * Поэтому объявлению не обязательно
     * писать "Львів" или "Харків"
     * внутри самого текста.
     */
    city: channelConfig.city ?? null,
    lat: null,
    lng: null,
    photos,
    dealType:
        channelConfig.dealType ??
        null,
    url: `https://t.me/${postPath}`,
    createdAt:
    msg.date,
  });
}
// Fetch one history page from the worker. Returns the parsed messages plus the
// smallest message id seen (the `beforeId` cursor for paging to older posts).
async function fetchWorkerPage(channel, beforeId, deadline) {
  const params = new URLSearchParams({ channel, limit: '100' });
  if (beforeId) params.set('beforeId', String(beforeId));
  // Cap the per-request wait by whatever budget remains, so a slow worker call
  // can't overrun the outer telegram budget.
  const budgetLeft = deadline === Infinity ? 15_000 : Math.max(1_000, deadline - Date.now());
  const res = await fetch(`${TG_WORKER_URL}/history?${params}`, {
    signal: AbortSignal.timeout(Math.min(15_000, budgetLeft)),
  });
  if (!res.ok) throw new Error(`tg-worker @${channel} HTTP ${res.status}`);
  const body = await res.json();
  if (!body.ok) throw new Error(body.error || `tg-worker @${channel} error`);
  return body;
}

// The worker returns up to 100 messages per call; page back via the `beforeId`
// cursor to cover the full freshness window. The early-stop keeps dead channels
// cheap (bail as soon as a page is entirely older than MAX_AGE_MS).
const TG_MAX_PAGES = 8;

export async function fetchChannel(
    channelConfig,
    country,
    filters = {},
    deadline = Infinity,
) {
  const channel =
      channelConfig.name;

  const listings = [];

  let beforeId =
      0;

  for (
      let page = 0;
      page < TG_MAX_PAGES;
      page++
  ) {
    if (
        Date.now() >=
        deadline
    ) {
      break;
    }

    const {
      messages,
      minId,
    } =
        await fetchWorkerPage(
            channel,
            beforeId,
            deadline,
        );

    if (
        !messages.length &&
        minId === null
    ) {
      break;
    }

    let oldestTs =
        null;

    for (
        const message
        of messages
        ) {
      const listing =
          messageToListing(
              message,
              channelConfig,
              country,
          );

      if (listing) {
        listings.push(
            listing,
        );
      }

      if (message.date) {
        const time =
            Date.parse(
                message.date,
            );

        if (
            !Number.isNaN(
                time,
            )
        ) {
          oldestTs =
              oldestTs === null
                  ? time
                  : Math.min(
                      oldestTs,
                      time,
                  );
        }
      }
    }

    if (
        minId === null ||
        minId === beforeId
    ) {
      break;
    }

    if (
        oldestTs &&
        Date.now() -
        oldestTs >
        MAX_AGE_MS
    ) {
      break;
    }

    beforeId =
        minId;
  }

  return listings;
}

// Fetch a channel with one retry, mirroring the previous adapter's resilience.
async function fetchChannelWithRetry(
    channelConfig,
    country,
    filters,
    deadline = Infinity,
) {
  for (
      let attempt = 0;
      attempt < 2;
      attempt++
  ) {
    try {
      const result =
          await fetchChannel(
              channelConfig,
              country,
              filters,
              deadline,
          );

      if (
          result.length > 0 ||
          attempt === 1
      ) {
        return result;
      }
    } catch (err) {
      if (
          attempt === 1
      ) {
        console.warn(
            `[telegram] @${channelConfig.name}: ` +
            `${err?.message ?? err}`,
        );

        return [];
      }
    }

    if (
        Date.now() >=
        deadline
    ) {
      return [];
    }

    await new Promise(
        (resolve) =>
            setTimeout(
                resolve,
                500,
            ),
    );
  }

  return [];
}
// Wall-clock budget for a whole telegram scrape, so one slow channel can't blow
// past the nginx proxy timeout and starve the fast OLX results.
const TG_BUDGET_MS = Number(process.env.TG_BUDGET_MS) || 12000;
const telegramChannelCursor =
    new Map();

const TG_CHANNELS_PER_RUN =
    Math.max(
        1,
        Number(
            process.env
                .TG_CHANNELS_PER_RUN,
        ) || 6,
    );

function selectTelegramChannels(
    country,
) {
  const all =
      (
          country.telegramChannels ??
          []
      )
          .map(normalizeChannelConfig,)
          .filter(Boolean);

  if (
      all.length <=
      TG_CHANNELS_PER_RUN
  ) {
    return {
      channels:
      all,

      complete:
          true,
    };
  }

  let start =
      telegramChannelCursor.get(
          country.code,
      );

  /*
   * После рестарта не начинаем
   * обязательно с первых каналов.
   */
  if (
      !Number.isInteger(
          start,
      )
  ) {
    start =
        (
            Math.floor(
                Date.now() /
                60_000,
            ) *
            TG_CHANNELS_PER_RUN
        ) %
        all.length;
  }

  const selected =
      [];

  for (
      let index = 0;
      index <
      TG_CHANNELS_PER_RUN;
      index++
  ) {
    selected.push(
        all[
        (
            start +
            index
        ) %
        all.length
            ],
    );
  }

  telegramChannelCursor.set(
      country.code,
      (
          start +
          TG_CHANNELS_PER_RUN
      ) %
      all.length,
  );

  return {
    channels:
    selected,

    complete:
        false,
  };
}

export async function scrapeTelegram(
    country,
    filters,
) {
  if (!TG_WORKER_URL) {
    throw new Error(
        'TG_WORKER_URL is not configured',
    );
  }

  const {
    channels,
    complete,
  } =
      selectTelegramChannels(
          country,
      );

  const CONCURRENCY =
      4;

  const deadline =
      Date.now() +
      TG_BUDGET_MS;

  const listings =
      [];

  for (
      let index = 0;
      index <
      channels.length;
      index +=
          CONCURRENCY
  ) {
    if (
        Date.now() >=
        deadline
    ) {
      break;
    }

    const batch =
        channels.slice(
            index,
            index +
            CONCURRENCY,
        );

    const results =
        await Promise.allSettled(
            batch.map(
                (channel) =>
                    fetchChannelWithRetry(
                        channel,
                        country,
                        filters,
                        deadline,
                    ),
            ),
        );

    for (
        const result
        of results
        ) {
      if (
          result.status ===
          'fulfilled'
      ) {
        listings.push(
            ...result.value,
        );
      }
    }
  }

  /*
   * complete=false здесь НЕ ошибка.
   *
   * Просто большой список каналов
   * намеренно обходим порциями.
   *
   * PostgreSQL постепенно
   * аккумулирует результаты.
   */
  return {
    listings,

    complete,

    partialExpected:
        !complete,

    processedChannels:
        channels.map(
            (channel) =>
                channel.name,
        ),
  };
}

function normalizeChannelConfig(value) {
  if (typeof value === 'string') {
    return {
      name: value,
      city: null,
      dealType: null,
    };
  }

  if (
      value &&
      typeof value === 'object' &&
      value.name
  ) {
    return {
      name:
          String(value.name),

      city:
          value.city
              ? String(value.city)
              : null,

      dealType:
          value.dealType
              ? String(value.dealType)
              : null,
    };
  }

  return null;
}