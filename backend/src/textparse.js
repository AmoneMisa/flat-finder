// Best-effort extraction of price / rooms / area from free-text posts
// (Reddit, Telegram, Threads) where there is no structured field.

const CURRENCY_WORDS = [
  [/(€|eur\b|euro)/i, 'EUR'],
  [/(\$|usd\b|у\.?е\.?|у\.о\.?|dollar|доллар)/i, 'USD'],
  [/(грн|uah\b|₴|гривн)/i, 'UAH'],
  [/(lei\b|ron\b)/i, 'RON'],
  [/(тенге|теңге|tenge|tg\b|kzt\b|₸)/i, 'KZT'],
  [/(сум|сўм|so[‘’ʻʼ'`]?m\b|som\b|uzs\b)/i, 'UZS'],
];

// Currency marker used to spot amounts written right next to a currency, e.g.
// "150 $", "$81500", "750€", "1 500 у.е". Lets us keep small hard-currency
// rents (a few hundred $/€) that the "must be ≥ 1000" fallback would drop.
const PRICE_SYMBOL =
  "(?:\\$|€|₸|₴|usd|eur|грн?\\.?|uah|lei|ron|тенге|тг|kzt|сум|сўм|so[‘’ʻʼ'`]?m|uzs|у\\.?е\\.?|доллар|евро)";
// A single amount: either grouped thousands ("1 500 000", "10.915.500") or a
// plain integer ("81500", "580"). The separator set excludes newlines so a
// floor and a price on separate lines ("Этаж: 3\n580€") never merge into 3580.
const PRICE_NUM = '\\d{1,3}(?:[ \\u00A0.,]\\d{3})+|\\d+';

export function parsePriceFromText(text, fallbackCurrency = '') {
  if (!text) return { price: null, currency: fallbackCurrency };

  let currency = fallbackCurrency;
  let explicit = false; // a currency was actually written in the text
  for (const [re, code] of CURRENCY_WORDS) {
    if (re.test(text)) {
      currency = code;
      explicit = true;
      break;
    }
  }

  let price = null;

  // A labelled base price outranks conditional prices elsewhere in the post.
  // Example: `Аренда: 400$` remains the main rent even when a later line says
  // `Для семьи — 450$`.
  {
    const labelled = text.match(
      new RegExp(`(?:цена|ціна|нарх(?:и)?|narx|price|стоимост[ьи]|аренд(?:а|ная\\s+плата)?|rent)\\s*[:\\-–—]?\\s*(${PRICE_NUM})`, 'i'),
    );
    if (labelled) {
      const n = Number(labelled[1].replace(/[\s.,]/g, ''));
      if (n >= 50 && n <= 5_000_000_000) price = n;
    }
  }

  // (1) Prefer a number sitting right next to a currency marker. These are
  // reliable even when small, so hard-currency rents like "150 $" survive.
  if (price == null) {
    let tagged = null;
    const reNumSym = new RegExp(`(${PRICE_NUM})\\s*${PRICE_SYMBOL}`, 'ig');
    const reSymNum = new RegExp(`${PRICE_SYMBOL}\\s*(${PRICE_NUM})`, 'ig');
    for (const re of [reNumSym, reSymNum]) {
      let m;
      while ((m = re.exec(text)) !== null) {
        const n = Number(m[1].replace(/[\s.,]/g, ''));
        if (n >= 50 && n <= 5_000_000_000 && (tagged == null || n > tagged)) tagged = n;
      }
    }
    price = tagged;
  }

  // (1b) Word/abbrev magnitudes: "5 миллионов", "1.2 млн", "1 млрд", "500 тыс".
  // Without this, "Цена 5 миллионов" captured only "5" (below the price floor)
  // and the listing showed no price. Applies the multiplier to the number.
  if (price == null) {
    const m = text.match(
      /(\d+(?:[.,]\d+)?)\s*(млрд|миллиард|billion|млн|миллион|million|mln|тысяч|тыс|минг|ming)/i,
    );
    if (m) {
      const base = Number(m[1].replace(',', '.'));
      const unit = m[2].toLowerCase();
      const mult = /млрд|миллиард|billion/.test(unit)
        ? 1e9
        : /млн|миллион|million|mln/.test(unit)
          ? 1e6
          : 1e3;
      const n = Math.round(base * mult);
      if (n >= 1000 && n <= 5_000_000_000) price = n;
    }
  }

  // (2) A number right after a price keyword ("Цена 450", "Narx 150",
  // "PRICE: 395", "Стоимость 550"). Reliable at any size even without a
  // currency symbol, which is common in Uzbek channels quoting bare USD.
  if (price == null) {
    const m = text.match(
      new RegExp(`(?:цена|ціна|нарх(?:и)?|narx|price|стоимост[ьи])\\s*[:\\-–—]?\\s*(${PRICE_NUM})`, 'i'),
    );
    if (m) {
      const n = Number(m[1].replace(/[\s.,]/g, ''));
      if (n >= 50 && n <= 5_000_000_000) price = n;
    }
  }

  // (3) Fallback: the largest plausible number with common thousands separators,
  // e.g. "1 500 000", "120.000", "85,000", "50000". A ≥1000 floor here avoids
  // mistaking areas/floors for a price when no currency is attached.
  if (price == null) {
    // Blank out phone numbers first so a phone like "8 707 338 72 55" is never
    // read as a price. A phone is a run of digits/separators with ≥10 digits
    // total; real prices in these posts stay well under that (e.g. "12 000 000"
    // = 8 digits), so the threshold cleanly separates the two.
    const cleaned = text.replace(/\+?\d[\d\s().-]{7,}\d/g, (seg) =>
      seg.replace(/\D/g, '').length >= 10 ? ' ' : seg,
    );
    const matches = cleaned.match(/\d{1,3}(?:[ \u00A0.,]\d{3})+|\d{4,}/g) || [];
    let best = null;
    for (const m of matches) {
      const digits = m.replace(/[\s.,]/g, '');
      // A leading zero marks a phone number / id, never a price ("050 863 10 68"
      // grouped into "050863"), so skip it to avoid reading phones as prices.
      if (digits[0] === '0') continue;
      const n = Number(digits);
      if (n >= 1000 && n <= 5_000_000_000 && (best == null || n > best)) best = n;
    }
    price = best;
  }

  // Uzbek channels quote bare USD for the small amounts and UZS only for the
  // millions. When no currency was written, disambiguate by magnitude so a bare
  // "450" becomes USD while "10 915 500" stays UZS.
  if (!explicit && fallbackCurrency === 'UZS' && price != null) {
    // Daily Uzbek listings commonly omit `so'm`: `Narxi 200 000 kunlik` is
    // 200,000 UZS/day, never USD. Monthly posts still use the established
    // small-number-as-USD convention (`450` -> USD, millions -> UZS).
    const dailyUzbek = /(?:kunlik|sutkaga|kecha[- ]?kunduz|посуточн|суточн)/i.test(text);
    currency = price >= 1_000_000 || (dailyUzbek && price >= 10_000) ? 'UZS' : 'USD';
  }

  return { price, currency };
}

const ok10 = (n) => (n >= 1 && n <= 10 ? n : null); // dwellings have 1–10 rooms

// Spelled-out room counts: "Двухкомнатная", "трёхкомнатная", "однокімнатна".
const WORD_ROOMS = {
  одно: 1, одн: 1, двух: 2, двох: 2, трех: 3, трёх: 3, трих: 3, трьох: 3,
  четырех: 4, четырёх: 4, чотирьох: 4, чотирох: 4, пяти: 5,
};

export function parseRoomsFromText(text) {
  if (!text) return null;
  // Basement shorthand: room count / zero / basement floor.
  const basement = text.match(/(?:^|\n)[^\d\r\n]{0,8}([1-9])\s*\/\s*0\s*\/\s*-1\s*(?:этаж|эт\.?)?[^\r\n]*(?:подвал|цоколь)/im);
  if (basement) return ok10(Number(basement[1]));
  // Central-Asian Telegram shorthand: room/floor/storeys, for example
  // "2/4/4". A superscript room count means the original layout was converted
  // ("2³/4/4" = a 2-room plan converted to 3 rooms, on floor 4 of 4), so the
  // effective room count is the superscript value.
  const compact = text.match(
    /(?:^|\n)[^\d\r\n]{0,8}([1-9])\s*([¹²³⁴⁵⁶⁷⁸⁹])?\s*\/\s*([0-9]{1,2})\s*\/\s*([0-9]{1,2})[.,;:]?(?=\s|$)/m,
  );
  if (compact) {
    const superscript = '¹²³⁴⁵⁶⁷⁸⁹'.indexOf(compact[2]) + 1;
    if (superscript) return ok10(superscript);
    const first = Number(compact[1]);
    const floor = Number(compact[3]);
    const last = Number(compact[4]);
    // A few Uzbek channels write the ambiguous compact form as
    // floor/storeys/rooms. The characteristic `2 / 2 / 3` has a valid 2/3
    // floor pair and otherwise no room count; preserve the standard
    // rooms/floor/storeys interpretation for forms such as `2/5/16`.
    if (first === floor && last > first && last <= 5) return ok10(last);
    return ok10(first);
  }
  // (B) number AFTER the label — the common Telegram form: "Количество
  // комнат: 3", "Комнат 1", "Комнаты: 2", "Xonalar soni: 3", "Number of
  // rooms - 2". Checked FIRST so a stray preceding number (e.g. in "Этаж 3
  // Комнат 1" the 3 belongs to the floor) doesn't get grabbed by the
  // number-first pattern below.
  // The label matches the room NOUN only, never the adjective ("1комнатная" is
  // handled by (A)): a `(?![а-яё])` boundary stops "комнат" from eating
  // "комнатная⏎9 этаж" and grabbing the floor as the room count. The gap before
  // the number is horizontal whitespace only, so it can never cross a line.
  const after = text.match(
    /(?:количество\s+комнат\w*|комнат(?:ы|а)?(?![а-яё])|кімнат(?:и|а)?(?![а-яіїґ])|xonalar\s*soni|xona\s*soni|number\s+of\s+rooms)[^\S\r\n]*[:\-–—]?[^\S\r\n]*(\d+)/i,
  );
  if (after) return ok10(Number(after[1]));

  // (A) number BEFORE the room word: "3 комнатная", "2-комн", "3-ком.",
  // "3 xona", "1 room". camer (RO), комн (RU), кімн (UA), xona/xonali (UZ),
  // бөлме/бөлмелі (KZ), room/bedroom (EN). We deliberately do NOT match a bare
  // "кв" — that is "кв.м" (area) or "квартал" (block), e.g. "Чиланзар 16кв".
  const before = text.match(
    /(\d+)\s*[-хx]?\s*(?:camer|комнатн|комн|ком\.|кімнатн|кімн|кім\.|room|bedroom|xonali|xona|хонали|хона|бөлмел|бөлме)|(\d+)\s*-\s*к(?:омн|\.?\s*кв)/i,
  );
  if (before) return ok10(Number(before[1] ?? before[2]));

  // (C) spelled-out count immediately before "комнат"/"кімнат".
  const word = text
    .toLowerCase()
    .match(/(одно|одн|двух|двох|тр[еёи]х|трьох|четыр[её]х|чотир(?:ьох|ох)|пяти)\s*-?\s*(?:комнат|кімнат)/);
  if (word) return ok10(WORD_ROOMS[word[1]] ?? null);

  return null;
}

// Non-residential / commercial listings (offices, retail, warehouses) that
// should not appear among housing results. Kept conservative so amenities like
// "магазин рядом" (shop nearby) don't wrongly flag a flat.
// Includes: offices, commercial/business centres, non-residential "помещение",
// retail/warehouse/production premises, land plots (sotix/sotka/соток/yer
// maydoni — not housing) and service/auto premises (car wash, repair bay).
const COMMERCIAL_RE =
  /(офис[ _|,/.]|под ?офис|офисн|\boffice\b|\bofis\b|кеңсе|коммерческ|commercial|бизнес[ -]?центр|не\s?жил(?:ое|ой|ый|ых|ым|ого)|помещени[ея]|торгов(?:ое|ая) ?площад|торгов(?:ое|ое помещ)|warehouse|склад(?!н|ыв)|производствен(?:ное|ых) ?помещ|spatiu comercial|birou|\d+\s*sot(?:ix|ka)|\d+\s*сот(?:ок|ка|ки|ых)|yer\s*maydoni|bosh\s*yer|уч[аа]сток\s*земл|servis\s*uchun|kassaprav|avtomoyka|автомойк|car\s?wash|шиномонтаж|салон\s*красот|zallik\s*saloni|beauty\s*salon|beauty[\s-]?кабинет|космет(?:ическ|олог)[а-яё]*\s*кабинет|массажн[а-яё]*\s*кабинет|маникюрн[а-яё]*\s*(?:кабинет|студи)|nail\s*(?:bar|studio|salon)|аренда\s+(?:beauty\s+)?кабинет|парикмахерск|барбершоп|barbershop|аренда\s+рабоч(?:его|ее)\s*мест|рабоч(?:ее|его)\s*мест[оае]\s+(?:мастер|для\s+мастер|под\s+)|оренд[аи]\s+робоч(?:ого|е)\s*місц|аренда\s+гараж|гараж[ае]?\s+(?:аренд|сда[её]тся|ijara)|\bgaraj\b|\bgarage\b|o[\u2018\u2019\u02bb\u02bc'`ʻʼ]?quv\s*xona|o[\u2018\u2019\u02bb\u02bc'`ʻʼ]?quv\s*markaz|учебн(?:ый|ое|ая|ого)\s*(?:класс|помещ|кабинет|центр)|под\s+(?:бар|каф[её]|ресторан|магазин|салон|склад|бизнес|спортпит|спорт\s*пит|аптек|пекарн|пункт|шоурум|showroom|офис)|шоурум|showroom|спортпит|sportpit|\bsklad(?:lar)?\b|\bombor(?:xona)?\b|(?:avto\s*)?ser?vis\s+(?:arenda|ijara|beriladi)|авто\s?сервис\s+(?:аренд|сда[её]тся)|детейлинг|detailing|^\s*парковк|avtoturargoh|sot(?:ish|uv)\w*\s*joy|savdo\s*(?:uchun|joy)|\bdo[\u2018\u2019'`ʻʼ]?kon\b|(?:аренд|сда[её]т|сдам|прода|продаж)[а-яё]*\s+(?:(?:в|под|аренду|готов[а-яё]*|действующ[а-яё]*|срочно|отдельн[а-яё]*|стоящ[а-яё]*|цел[а-яё]*)\s+){0,3}(?:здани|каф[её])|бутик|[|,/]\s*(?:салон|бутик|аптек)|arenda\w*\s+joy|ijara\w*\s+joy|готов[а-яё]*\s+бизнес|tayyor\s+biznes|бизнес\s+(?:ресторан|каф[её]|магазин)|(?:сда[её]тся|аренда|прода[её]тся)\s+(?:готов[а-яё]*\s+)?(?:ресторан|каф[её]|чайхан|choyxona)|marojni|muzqaymoq)/i;

export function looksCommercial(text) {
  return text ? COMMERCIAL_RE.test(text) : false;
}

// Words that end a complex name: everything after them describes the flat, not
// the building. Without this the capture ran on for its full character budget
// and swallowed the rest of the title, often cutting a word in half
// ("Манзара Сити 2комнатная новая ремонт ме").
const RC_STOP_WORD_RE =
  /^(?:жк|жм|продаётся|продается|продам|продажа|продаю|срочно|сдаётся|сдается|сдаю|сдам|аренда|арендую|новая|новый|новое|новые|новостройка|вторичка|квартира|квартиры|квартиру|комната|комнаты|комнат|комнатная|комнатной|этаж|этажа|этаж[её]м|ремонт|ремонтом|евроремонт|мебель|мебелью|мебелированная|дом|дома|тел|телефон|цена|торг|собственник|риелтор|посредник|uy|kvartira|xonali|sotiladi|ijaraga|yangi|arzon|tel|narx|new|newbuild|apartment|apartments|flat|for|sale|rent|rooms?|floor|предлагается|предлагаются|предлагаем|продаже|продаж|куплю|обмен|просторные|просторная|две|три|четыре|пять|район|районе|районы|туман|тумани|tumani|district|массив|массиве|massiv|метро|metro|рядом|около|возле|яндекс|город|шахар|shahar)$/iu;

// Tokens that are attributes rather than name parts: "2комнатная", "3/7/12",
// "56кв", "100м2", bare numbers.
const RC_ATTRIBUTE_TOKEN_RE = /^\d|^[\d/]+$|^[a-zа-яё]?\d+(?:[а-яёa-z]{1,4})?$/iu;

// Latin brand-style names lead many titles without any "ЖК" in front of them:
// "PARKENT AVENUE Мирзо-Улугбекский район", "London | 4/7/10". Marketing words
// look the same but never name a building.
const RC_LATIN_NOISE_RE =
  /^(?:vip|lux|luxe|elite|premium|euro|evro|new|top|super|best|hot|urgent|srochno|arenda|ijara|sotiladi|sale|rent|for|home|house|flat|apartment|apartments|kvartira|tashkent|toshkent|wifi|wi|fi|tv|ac|internet|telegram|yandex|google|instagram|whatsapp|iphone|samsung|lg|bosch|artel|km|km2|m2|sqm|usd|uzs|eur)$/iu;

const RC_LATIN_WORD_RE = /^[A-Za-z][A-Za-z'’\-]{1,}$/u;

// Only the headline is searched for a bare Latin name. Descriptions are full of
// Latin words that name nothing ("Wi-Fi", "Bosch", a Telegram handle), and the
// building's name, when the post leads with it, is in the first few words.
const RC_HEADLINE_TOKENS = 12;

/**
 * A Latin brand-style name in the headline, when it reads as a name rather
 * than a marketing prefix — "PARKENT AVENUE Мирзо-Улугбекский район",
 * "Юнусобод Манзара Hi Town 2комнатная". Only used when the post never
 * writes "ЖК".
 */
function leadingLatinName(text) {
  // A Latin run only reads as a brand when the post around it is Cyrillic.
  // Plenty of Tashkent posts are written entirely in Uzbek Latin, where the
  // same rule happily returned "Bez makler" or "Manzil Samarqand Darvoza".
  const cyrillic = (String(text).match(/[а-яёіїґ]/giu) || []).length;
  const latin = (String(text).match(/[a-z]/giu) || []).length;
  if (cyrillic <= latin) return null;

  const tokens = String(text).trim().split(/[\s|,;:!]+/).filter(Boolean).slice(0, RC_HEADLINE_TOKENS);
  const runs = [];
  let current = [];

  for (const token of tokens) {
    const clean = token.replace(/^[«»"'„“]+|[«»"'„“!|,]+$/g, '');
    // "Wi-Fi" must read as "wifi" for the noise check to catch it.
    const bare = clean.replace(/[-'’]/g, '');
    const usable =
      RC_LATIN_WORD_RE.test(clean) &&
      !RC_LATIN_NOISE_RE.test(clean) &&
      !RC_LATIN_NOISE_RE.test(bare) &&
      !RC_STOP_WORD_RE.test(clean);

    if (usable && current.length < 3) {
      current.push(clean);
      continue;
    }
    if (current.length) runs.push(current);
    current = usable ? [clean] : [];
  }
  if (current.length) runs.push(current);

  // A run that is the whole headline is as likely to be an English description;
  // a name is surrounded by the rest of the post.
  const named = runs.find(
    (run) => run.some((word) => word.length >= 3) && run.length < tokens.length,
  );
  return named ? named.join(' ') : null;
}

const RC_DISTRICT_MARKER_RE = /^(?:район|районе|районы|туман|тумани|tumani|district)$/iu;

const RC_MARKER_RE =
  /(?:жк|жм|ж\/к|residential complex|ansamblu(?: rezidential)?|turar[- ]?joy majmuasi)\s*/i;

// Residential-complex ("ЖК ...", "residential complex", "ЖМ", "TP", RO "ansamblu")
// name, when the post names one. Returns a short trimmed name or null.
export function parseResidentialComplex(text) {
  if (!text) return null;
  const marker = text.match(RC_MARKER_RE);
  if (!marker) return leadingLatinName(text);
  const rest = text
    .slice(marker.index + marker[0].length)
    .replace(/^[\s:；;—–\-·•]+/, '');

  // A quoted name is authoritative — take it whole, however it is written.
  const quoted = rest.match(/^["'«»„“]\s*([^"'«»„“\n]{2,60})["'«»„“]?/);
  const candidate = quoted
    ? quoted[1]
    // Otherwise read the plain run the old expression used to take wholesale.
    : (rest.match(/^([^"'«»„“\n,.;:()!|]{2,60})/) || [, ''])[1];

  const parsed = String(candidate)
    .trim()
    // Hashtags commonly remove spaces: `#ЖКАссаломСохил`.
    .replace(/([\p{Ll}\d])(\p{Lu})/gu, '$1 $2')
    .replace(/\s{2,}/g, ' ')
    .split(/\s+/)
    // A name is a couple of words, and it ends where the flat's description
    // begins — never mid-word at a character budget.
    .reduce((words, token) => {
      if (words.stopped || words.list.length >= 4) return { ...words, stopped: true };
      const clean = token.replace(/^[«»"'„“]+|[«»"'„“!|,]+$/g, '');
      if (!clean || RC_STOP_WORD_RE.test(clean) || RC_ATTRIBUTE_TOKEN_RE.test(clean)) {
        return { ...words, stopped: true, by: clean };
      }
      return { list: [...words.list, clean], stopped: false, by: words.by };
    }, { list: [], stopped: false, by: '' })

  // "Bobur Residence Яккасарай район": the word that stopped us proves the one
  // before it was the district, not part of the name.
  const words = RC_DISTRICT_MARKER_RE.test(parsed.by) ? parsed.list.slice(0, -1) : parsed.list;
  while (words.length > 1 && [...words[words.length - 1]].length <= 2) words.pop();
  const name = words.join(' ').trim();

  // Reject captures that are just a number or too short to be a name.
  return /[a-zA-Zа-яёіїґ]{2,}/i.test(name) ? name : null;
}

export function parseAreaFromText(text) {
  if (!text) return null;
  const m =
    // "80 квадратов" / "80 квадрат" is a common colloquial form for m².
    text.match(/(\d{2,4})\s*(?:m2|m²|мкв|м2|м²|sq ?m|кв\.?\s*м|квадрат[а-яё]*)/i) ||
    // Telegram shorthand often puts a bare `кв` area after
    // rooms/floor/storeys: `2/5/16 56кв`. Requiring the three-part prefix
    // avoids mistaking district labels such as `Chilonzor 16кв` for an area.
    text.match(/(?:^|\n)[^\d\r\n]{0,8}[1-9]\s*[¹²³⁴⁵⁶⁷⁸⁹]?\s*\/\s*[0-9]{1,2}\s*\/\s*[0-9]{1,2}\s+(\d{2,4})\s*кв(?=\s|$)/im);
  return m ? Number(m[1]) : null;
}

// Classify a listing's deal type from its text. Returns one of
// 'sale' | 'longRent' | 'shortRent' | null (unknown). Short-term is checked
// first because those posts almost always also contain generic rent words.
export function classifyDealType(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  // Short-term: RO/RU/UA + UZ (sutkaga/kunlik/kecha) + KZ (тәулік/сағаттық).
  // "суточн" covers both "посуточная" and the bare adjective "суточная
  // квартира"; the (?<!кругло) lookbehind keeps "круглосуточная охрана/
  // видеонаблюдение" (24-hour security, common in sale/long-term posts) from
  // being misread as short-term.
  if (/(regim hotelier|in regim|posutoc|подобов|подобно|(?<!кругло)суточн|почасов|(?:за|на)\s+сутки|сутка(?:ми)?|per (night|day)|daily rent|short[\s-]?term|nightly|sutkaga|kunlik|kecha[- ]?kunduz|тәулік|тәулiк|сағаттық)/i.test(t))
    return 'shortRent';
  // Sale: RO/RU/UA/EN + UZ (sotiladi/sotuv/sotaman) + KZ (сатылады/сату).
  // Checked BEFORE long-term rent because sale posts routinely pitch rental
  // income ("подойдёт для сдачи в аренду"), which would otherwise be misread as
  // a rental. A negation guard avoids "не продаётся" flipping a rental to sale.
  const sale =
    /(de v[aâ]nzare|v[aâ]nzare|прода[жёе]|продам|на продаж|for sale|\bsale\b|купит|kupit|to buy|sotiladi|sotuv|sotaman|sotib|сатылады|сату|сатамын)/i.test(t) &&
    !/не\s+прода/i.test(t);
  if (sale) return 'sale';
  // Long-term rent: RO/RU/UA/EN + UZ (ijara/arenda) + KZ (жалға/жалдау/аренда).
  if (/(inchiri|închiri|de închiriat|оренд|аренд|rent\b|for rent|сдам|сдаю|сдаётся|сдается|здам|найм|долгосроч|довгостро|ijara|ijaraga|ижара|arenda|жалға|жалдау|жалга|жал\b|sherik(?:ka|lik)|шерик(?:ка|лик)|oila(?:ga)?\s+qo['’`]?yiladi|oila(?:ga)?\s+quyiladi|(?:хонали|квартир)[^\r\n]{0,100}турибди[^\r\n]{0,30}\d+\s*\$|квартира\s+бор)/i.test(t))
    return 'longRent';
  return null;
}

// Floor and total floors, e.g. "5/9", "этаж 5 из 9", "3-й этаж", "5-qavat",
// "floor 5". Returns { floor, totalFloors } with nulls when not found.
export function parseFloor(text) {
  if (!text) return { floor: null, totalFloors: null };
  const t = text.toLowerCase();
  // The "эт." abbreviation requires its dot: as a bare "эт" the alternation
  // backtracked into "этажный"/"этажей" (whose real suffixes are rejected below)
  // and matched a building's storey count as the flat's floor.
  const FLOOR = '(?:этаж(?:да)?|поверх|qavat|қабат|қабатт|etaj|floor|эт\\.)';
  const ok = (f, total) =>
    f >= 0 && f <= 200 && (total == null || (total >= f && total <= 200));

  if (/(?:^|\n)[^\d\r\n]{0,8}[1-9]\s*\/\s*0\s*\/\s*-1\s*(?:этаж|эт\.?)?[^\r\n]*(?:подвал|цоколь)/im.test(t)) {
    return { floor: -1, totalFloors: null };
  }

  // Central-Asian room/floor/storeys shorthand. The optional superscript after
  // the room count describes a converted layout and is irrelevant to floors.
  const compact = t.match(
    /(?:^|\n)[^\d\r\n]{0,8}[1-9]\s*[¹²³⁴⁵⁶⁷⁸⁹]?\s*\/\s*([0-9]{1,2})\s*\/\s*([0-9]{1,2})[.,;:]?(?=\s|$)/m,
  );
  if (compact) {
    const floor = Number(compact[1]);
    const total = Number(compact[2]);
    if (floor >= 1 && floor <= 40 && total >= 2 && total <= 40 && floor <= total) {
      return { floor, totalFloors: total };
    }
  }

  // Uzbek/Russian labelled pairs that put the floor word between the values,
  // for example "2-qavat / 14-qavatli" or "2 этаж из 14 этажей".
  const labelledPair =
    t.match(/([1-9]\d?)\s*-?\s*(?:qavat|этаж|поверх|қабат)\s*(?:\/|из|iz|of)\s*([1-9]\d?)\s*-?\s*(?:qavatli|qavat|этаж(?:ей|ный)?|поверх(?:ів|овий)?|қабатты?)/i);
  if (labelledPair) {
    const floor = Number(labelledPair[1]);
    const total = Number(labelledPair[2]);
    if (floor <= 40 && total <= 40 && floor <= total) return { floor, totalFloors: total };
  }

  // "X/Y" (or "X из Y" / "X of Y") with a floor word on either side.
  const SEP = '(?:\\/|из|iz|of)';
  let m =
    t.match(new RegExp(`${FLOOR}\\D{0,4}(\\d{1,2})\\s*${SEP}\\s*(\\d{1,2})`)) ||
    t.match(new RegExp(`(\\d{1,2})\\s*${SEP}\\s*(\\d{1,2})\\s*${FLOOR}`));
  if (m) {
    const floor = Number(m[1]);
    const total = Number(m[2]);
    if (ok(floor, total)) return { floor, totalFloors: total };
  }

  // Single floor: "X этаж", "X-й этаж", "floor X", "этаж: X". A JS `\b` after a
  // Cyrillic letter is unreliable (Cyrillic isn't `\w`), so we use an explicit
  // "not followed by another letter" lookahead instead. This both fixes "2 этаж"
  // (which `\b` failed to match) and still rejects "5-этажный дом" (5-storey).
  // Reject only the suffixes that change the meaning, not every letter: a bare
  // "(?![a-zа-яёіїґ])" also killed the valid prepositional/genitive forms, so
  // "на 3 этаже" parsed as no floor at all. Blocked: этажный/этажная (a
  // 5-storey BUILDING), этажей/этажність (total floors), этажка, floors.
  const NOT_LETTER = '(?!н|ей|ів|ност|ка|ки|s)';
  // The number-before-floor form uses horizontal whitespace only, so a count on
  // the previous line ("Комнат: 4⏎Этаж:") can't be grabbed as the floor.
  let s =
    // Ordinal endings: RU short forms decline ("на 5-м/5-ом/2-го этаже"), so the
    // list needs more than "й" — without "м" the most common spoken form,
    // "на 5-м этаже", parsed as no floor at all. Longest alternatives first.
    t.match(new RegExp(`(\\d{1,2})[^\\S\\r\\n]*-?[^\\S\\r\\n]*(?:го|ом|ым|ой|ий|nd|rd|th|st|й|м|е)?[^\\S\\r\\n]*${FLOOR}${NOT_LETTER}`)) ||
    t.match(new RegExp(`${FLOOR}\\s*[:№#]?\\s*(\\d{1,2})\\b`));
  if (s) {
    const floor = Number(s[1]);
    if (ok(floor, null)) {
      // Building height stated on its own line ("Этажность: 4",
      // "qavatlar soni: 9", "этажей 12") fills totalFloors when present.
      const tm = t.match(
        /(?:этажность|этажей|поверхови|поверховість|qavatlar(?:\s*soni)?|qavatli|қабатты?)\D{0,6}(\d{1,2})/,
      );
      const leadingTotal = t.match(
        /([1-9]\d?)\s*-?\s*(?:этажн[а-яё]*|поверхов[а-яіїґ]*|qavatli|қабатты?)\s*(?:дом|здани|будин|uy|bino)?/i,
      );
      const total = tm ? Number(tm[1]) : leadingTotal ? Number(leadingTotal[1]) : null;
      return { floor, totalFloors: total && total >= floor && total <= 200 ? total : null };
    }
  }

  // Last resort: a bare "N/M" with no floor word, the compact form Telegram
  // posts favour ("вул. ... 193-А. 1/9 23м"). Heavily guarded to avoid dates and
  // fractions: both sides must be plausible floors (1–40), floor ≤ total, total
  // ≥ 2, and the pair must not be part of a longer number/date sequence
  // ("01/09/2025" is excluded by the trailing lookahead).
  const bare = t.match(/(?<![\d/])([1-9]\d?)\s*\/\s*([1-9]\d?)(?![\d/])/);
  if (bare) {
    const floor = Number(bare[1]);
    const total = Number(bare[2]);
    if (floor >= 1 && floor <= 40 && total >= 2 && total <= 40 && floor <= total) {
      return { floor, totalFloors: total };
    }
  }
  return { floor: null, totalFloors: null };
}

// Construction year. Requires a build-related keyword nearby (or a year followed
// by a year-unit) to avoid matching random 4-digit numbers.
export function parseYear(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  const YEAR = '(19\\d{2}|20[0-3]\\d)';
  const KW =
    '(?:год(?:а)? постройк|построен|сдача|рік побудов|побудован|введен в експлуат|' +
    'built|year built|construc[cțt]ie|an construc|qurilgan|qurilish yil|salingan|' +
    'жыл(?:ы)? салынған)';
  let m =
    t.match(new RegExp(`${KW}\\D{0,12}${YEAR}`)) ||
    t.match(new RegExp(`${YEAR}\\s*(?:г\\.?|года|й\\.?|йил|жыл|year)\\b`));
  if (m) {
    const y = Number(m[1]);
    const max = new Date().getFullYear() + 3;
    if (y >= 1900 && y <= max) return y;
  }
  return null;
}

// Number of sleeping rooms / bedrooms (distinct from total rooms).
export function parseBedrooms(text) {
  if (!text) return null;
  const m = text.match(
    /(\d+)\s*-?\s*(?:bedroom|спальн|спалень|dormitoare|dormitor|yotoq(?:xona)?|жатын)/i,
  );
  return m ? Number(m[1]) : null;
}

// Target-audience restriction stated in the post, or null. Family is checked
// first so "for a family with girls" resolves to family.
export function classifyAudience(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  // Families and single tenants are both accepted: this is not a restriction.
  if (/(?:семейн|сімейн|для семь|для сім)[^.\n]{0,80}(?:одиноч|мужчин|женщин|чоловік|жінок)|(?:одиноч|мужчин|женщин|чоловік|жінок)[^.\n]{0,80}(?:семейн|сімейн|для семь|для сім)/.test(t))
    return null;
  if (/(для семь|семейн|сімейн|для сім|для родин|for famil|families?|pentru famil|oila(?:ga| uchun|\s+qo['’`]?yiladi|\s+quyiladi)|оила|отбасы)/.test(t))
    return 'family';
  if (/(девуш|девоч|для дівч|дівчат|for girls|for women|only girls|doar fete|\bfete\b|qiz(?:lar|la)?(?:ga| uchun)?|(?:қ|к)из(?:лар|ла)?|қыздар)/.test(t))
    return 'women';
  if (/(парн(ей|ям)|для мужчин|мужчинам|для хлопц|for men\b|for boys|doar b[aă]ie[țt]i|yigit(lar)?(ga| uchun)?|(?:ў|у)гил\s*бол|жігіт|ер адам)/.test(t))
    return 'men';
  return null;
}

// Best-effort seller contact: an international phone (leading +), a local phone
// introduced by a phone keyword, or an @handle. Kept conservative so it does not
// mistake large prices (e.g. UZS amounts) for phone numbers.
export function parseContact(text) {
  if (!text) return null;

  const intl = text.match(/\+\d[\d\s().-]{7,}\d/);
  if (intl) {
    const digits = intl[0].replace(/\D/g, '');
    if (digits.length >= 10 && digits.length <= 15) return '+' + digits;
  }

  const kw = text.match(
    /(?:tel|тел|phone|моб|whats?app|viber|telegram|звонит|звоніть|aloqa|byla|contact)[^\d+]{0,8}(\+?\d[\d\s().-]{6,}\d)/i,
  );
  if (kw) {
    const digits = kw[1].replace(/\D/g, '');
    if (digits.length >= 9 && digits.length <= 15) return kw[1].trim();
  }

  // Some Telegram posts put the marker after a local number: `771443473 tel`.
  const trailingKw = text.match(
    /(\+?\d[\d\s().-]{6,}\d)\s*(?:tel|тел(?:ефон)?|phone|моб|whats?app|viber|telegram|aloqa|contact)(?=$|[^\p{L}\p{N}_])/iu,
  );
  if (trailingKw) {
    const digits = trailingKw[1].replace(/\D/g, '');
    if (digits.length >= 9 && digits.length <= 15) return trailingKw[1].trim();
  }

  const handle = text.match(/@[A-Za-z0-9_]{4,32}/);
  if (handle) return handle[0];

  return null;
}

// Whether pets are explicitly allowed. Returns true / false / null (unstated).
// We only return false on an explicit ban so "unknown" stays lenient.
export function classifyPets(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  if (/(без ?животн|нельзя с животными|без[^.\n]{0,20}тварин|no pets|pets not allowed|fara animale|hayvon.*mumkin emas|үй жануар.*болмайды)/i.test(t))
    return false;
  if (/(можно с животными|можно с питомц|з тваринами можна|з тваринами дозвол|pets? ?(allowed|ok|friendly)|se accepta animale|animale acceptate|uy hayvon.*mumkin|үй жануар.*болады)/i.test(t))
    return true;
  return null;
}

// Whether children are explicitly allowed. Same true/false/null convention.
export function classifyChildren(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  if (/(без ?детей|нельзя с детьми|без[^.\n]{0,20}дітей|no (kids|children)|children not allowed|fara copii|bolalar.*mumkin emas|балалар.*болмайды)/i.test(t))
    return false;
  if (/(можно с детьми|можно с ребен|з дітьми можна|з дітьми дозвол|children ?(allowed|ok|welcome)|kids ?(ok|welcome)|se accepta copii|copii acceptati|bolalar.*mumkin|балалар.*болады)/i.test(t))
    return true;
  return null;
}

export function looksRoomOnly(text) {
  if (!text) {
    return false;
  }

  return /подселени|підселен|комнату\s+в|кімнату\s+в|сда[её]тся\s+комната|сдается\s+комната|сдам\s+комнату|здам\s+кімнат|room\s+in\s+a\s+(?:shared\s+)?flat|room\s+for\s+rent|shared\s+(?:flat|apartment|room)|roommate|flatmate|xona\s+ijaraga|xona\s+beriladi|sherik(?:ka|lik)|шерик(?:ка|лик)|(?:1|бир)\s*та\s*(?:бола|киши|қиз|киз)\s*керак|1\s*хонага[^\r\n]{0,40}(?:киши|одам)\s*турилади|бөлме\s+жалға|închiriez\s+camer[ăa]|ищу[^\r\n]{0,60}сосед|ищем[^\r\n]{0,60}сосед|нужен[^\r\n]{0,60}сосед|нужна[^\r\n]{0,60}сосед|шукаю[^\r\n]{0,60}сусід|шукаємо[^\r\n]{0,60}сусід|потрібен[^\r\n]{0,60}сусід|потрібна[^\r\n]{0,60}сусід|співмешкан|співжител|соседк|сусідк/i.test(
      text,
  );
}

/**
 * Demand-side housing post:
 *
 *   "ищу квартиру"
 *   "ищем 2-комнатную квартиру"
 *   "сниму квартиру"
 *   "нужна квартира"
 *   "шукаю квартиру в оренду"
 *   "шукаємо 2-кімнатну квартиру"
 *   "потрібна квартира"
 *
 * Roommate / shared-flat posts are deliberately NOT classified
 * as wanted housing and remain in Flat Finder.
 */
export function looksHousingWanted(text) {
  if (!text) {
    return false;
  }

  const value =
      String(text)
          .replace(/\s+/g, ' ')
          .trim();

  if (!value) {
    return false;
  }

  /*
   * Explicit exception:
   *
   * "ищу на подселение"
   * "ищу соседку"
   * "шукаю співмешканця"
   */
  if (looksRoomOnly(value)) {
    return false;
  }

  const seeker =
      /ищу|ищем|ищет|ищут|шукаю|шукаємо|шукає|шукають|сниму|снимем|снимет|зніму|знімемо|зніме|хочу\s+снять|хотим\s+снять|хочемо\s+зняти|хочу\s+зняти|хочу\s+орендувати|хочемо\s+орендувати|потрібн(?:а|е|ий)|нужн(?:а|о|ы|ен)/iu;

  const housing =
      /квартир[\p{L}-]*|кімнат[\p{L}-]*|комнат[\p{L}-]*|будин[\p{L}-]*|житл[\p{L}-]*|жиль[\p{L}-]*|апартамент[\p{L}-]*|студи[\p{L}-]*|однушк[\p{L}-]*|двушк[\p{L}-]*|тр[её]шк[\p{L}-]*|коттедж[\p{L}-]*|\d+\s*[-–]?\s*(?:к|кк|кімнатн[\p{L}-]*|комнатн[\p{L}-]*)/iu;

  if (
      seeker.test(value) &&
      housing.test(value)
  ) {
    return true;
  }

  /*
   * Частые объявления без слова
   * "квартира":
   *
   * "сниму 2к"
   * "шукаю 1к"
   */
  return /(?:ищу|ищем|шукаю|шукаємо|сниму|зніму)[\s\S]{0,50}\d+\s*[-–]?\s*[кk](?:\s|$|[,.])/iu.test(
      value,
  );
}

// Security deposit required? true/false/null. Also returns the amount when the
// post states one (e.g. "залог 500$").
export function parseDeposit(text) {
  if (!text) return { required: null, amount: null };
  const t = text.toLowerCase();
  const KW = '(?:залог|заклад|депозит|deposit|garan[țt]ie|kaus|kafolat|кепіл)';
  if (!new RegExp(KW, 'i').test(t)) return { required: null, amount: null };
  if (/(без ?залог|без ?депозит|no deposit|fara garantie|депозит ?не ?требует)/i.test(t))
    return { required: false, amount: null };

  // Amounts must be on the same line as the deposit marker. Previously `\s`
  // crossed into the next line and turned a following +998 phone number into a
  // huge deposit. Strip phone-shaped runs first in case contact data is written
  // on the same line, then accept a grouped amount or a bounded plain integer.
  const tail = t.match(new RegExp(`${KW}([^\\r\\n]{0,80})`, 'i'))?.[1] || '';
  const withoutPhones = tail.replace(/\+?\d[\d\s().-]{7,}\d/g, (segment) =>
    segment.replace(/\D/g, '').length >= 9 ? ' ' : segment,
  );
  const m = withoutPhones.match(/(?:^|[^\d])(\d{1,3}(?:[ \u00a0.,]\d{3})+|\d{2,8})(?!\d)/);
  const amount = m ? Number(m[1].replace(/[\s.,]/g, '')) : null;
  // A deposit is often quoted in a different currency from the rent (e.g. rent
  // in UZS but "\u0414\u0435\u043f\u043e\u0437\u0438\u0442 1000USD"). Capture the currency written next to the
  // amount so the UI stops mislabelling it with the listing's currency.
  let currency = null;
  if (m) {
    const near = withoutPhones.slice(Math.max(0, m.index), m.index + m[0].length + 12);
    if (/\$|usd|\u0434\u043e\u043b\u043b\u0430\u0440|\u0443\.?\u0435\.?|\b\u0443\u0435\b/i.test(near)) currency = 'USD';
    else if (/\u20ac|eur|\u0435\u0432\u0440\u043e/i.test(near)) currency = 'EUR';
    else if (/\u0441\u0443\u043c|so'?m|uzs/i.test(near)) currency = 'UZS';
    else if (/\u0442\u0433|\u20b8|kzt|\u0442\u0435\u043d\u0433\u0435/i.test(near)) currency = 'KZT';
    else if (/\u0433\u0440\u043d|\u20b4|uah|\u0433\u0440\u0438\u0432\u043d/i.test(near)) currency = 'UAH';
    else if (/lei|ron/i.test(near)) currency = 'RON';
  }
  return {
    required: true,
    amount: amount && amount >= 10 ? amount : null,
    currency: amount && amount >= 10 ? currency : null,
  };
}

// Agency commission. Returns { has: bool|null, percent: number|null } — percent
// is filled when the post states one (e.g. "комиссия 50%").
export function parseCommission(text) {
  if (!text) return { has: null, percent: null };
  const t = text.toLowerCase();
  // Uzbek Telegram realtor shorthand: `M50%` / Cyrillic `М50%` means
  // makler commission 50%, even when the word makler is omitted.
  const shorthand = t.match(/(?:^|[^\p{L}\p{N}_])[mм]\s*[:.\-]?\s*(\d{1,3})\s*%/iu);
  if (shorthand) {
    const percent = Number(shorthand[1]);
    return { has: true, percent: percent <= 100 ? percent : null };
  }
  const KW = '(?:комисси|комісі|commission|comision|komissiya|комиссионн|ри[еэ]?лтор|ри[еэ]?лтер|услуг[аи]?\\s*ри[еэ]?лтор|маклер|makler|rieltor|vositachi)';
  if (/(без ?комисси|без ?комісі|no commission|fara comision|fără comision|без ?комиссионн)/i.test(t))
    return { has: false, percent: 0 };
  if (!new RegExp(KW, 'i').test(t)) return { has: null, percent: null };
  const m = t.match(new RegExp(`${KW}[^\\d]{0,15}(\\d{1,3})\\s*%`, 'i'));
  const percent = m ? Number(m[1]) : null;
  return { has: true, percent: percent != null && percent <= 100 ? percent : null };
}

// Whether a post was placed by a realtor / broker / agency rather than the
// owner. Telegram posts have no structured business flag (unlike OLX), so we
// infer it from the text: an explicit realtor/broker/agency word, or a stated
// "realtor fee / agency service" charge. Returns true when such a signal is
// present and not negated ("без посредников", "vositachisiz"), otherwise false.
const AGENCY_RE =
  /(ри[еэ]л?тор|реал?тор|макл[её]р|агентств|агент\s+по\s+недвиж|услуги\s+агентств|реал?тор\s*хак|макл[её]р\s*хак|rieltor|makler|vositachi(?!siz)|agentlik|realtor|real\s*estate\s*agen|broker|брокер|(?:^|[^\p{L}\p{N}_])[mм]\s*\d{1,3}\s*%)/iu;
const NO_AGENCY_RE =
  /(без\s+посредник|без\s+ри[еэ]л?тор|без\s+макл|без\s+агент|no\s+agency|fara\s+intermediari|vositachisiz|egasidan|иесінен)/i;

export function classifyAgency(text) {
  if (!text) return false;
  if (NO_AGENCY_RE.test(text)) return false;
  return AGENCY_RE.test(text);
}

export function guessPropertyType(text) {
  if (!text) return 'flat';
  // Prefer an explicit apartment word. Real-estate copy often says
  // "квартира в новом доме"; checking the generic house word first used to
  // misclassify those rows as houses.
  if (/(apartment|apartament|квартир|kvartira|пәтер|квартиралар|xonadon)/i.test(text)) {
    return 'flat';
  }
  // house (EN), casa (RO), dom/дом (RU), будин (UA), коттедж/villa/вілл/вилл,
  // hovli (UZ), үй (KZ). Do not treat Uzbek "uy" alone as a detached house:
  // it commonly means home/apartment in phrases such as "uy yangi remontdan
  // chiqqan" and was misclassifying ordinary Tashkent flats.
  return /(?:\b(?:house|casa|dom|villa|hovli)\b|будин|коттедж|вілл|вилл|(?:^|[^\p{L}\p{N}_])(?:дом|үй)(?=$|[^\p{L}\p{N}_]))/iu.test(text)
    ? 'house'
    : 'flat';
}

// --- Amenities & structured extras (spec table) -----------------------------
// Positive-only signals unless noted: `true` when the post mentions the feature,
// `null` when it doesn't (free text can rarely prove absence). EN/RU/UA/UZ/KZ/RO.

// Balcony or loggia present.
export function parseBalcony(text) {
  if (!text) return null;
  return /(балкон|лоджи|balkon|ayvon|balcon|loggia|balcony)/i.test(text) ? true : null;
}

// Air-conditioner / split system present.
export function parseAirConditioner(text) {
  if (!text) return null;
  return /([кk]ондицион|сплит[- ]?систем|konditsioner|kondisaner|kansaner|klimat|air ?con|\bA\/?C\b|aer condi[țt]ionat)/i.test(text)
    ? true
    : null;
}

// Furnishing is tri-state. Only explicit furniture words produce true/false;
// appliances alone are not enough to claim that a property is furnished.
export function parseFurnished(text) {
  if (!text) return null;
  if (/(без\s+мебел|пустая\s+квартир|unfurnished|nemobilat|mebelsiz|jihozlanmagan)/i.test(text)) return false;
  return /(с\s+мебел|меблирован|мебел|furnished|mobilat|mebelli|jihozlangan|spalni|spaln[iy]\s+garnitur|yotoq\s+mebel)/i.test(text)
    ? true
    : null;
}

// Natural-gas supply to the flat (NOT a nearby filling station). Guards against
// "газон" (lawn). Returns true / false (explicit "no gas") / null.
export function parseGasSupply(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  if (/(без ?газа|нет ?газа|no gas|gaz ?yo['’]?q)/i.test(t)) return false;
  return /(?:^|[^а-яё])газ(?!он)|метан|\bgaz\b|\bgas\b(?! ?stat)|aragaz|gaz ta['’]?min/i.test(t) ? true : null;
}

// New-build / novostroyka flag from text (buildingYear recency is added in
// makeListing). Returns true / null.
export function parseNewBuilding(text) {
  if (!text) return null;
  return /(новостро|новобуд|новый ?дом|new ?buil|newly ?built|yangi ?(bino|qurilgan|uy)|n[oa]v[oa]sti?roy|novostroy|bloc ?nou)/i.test(text)
    ? true
    : null;
}

// Number of bathrooms / санузлы. "2 санузла", "sanuzel 2", "2 bathrooms".
export function parseBathrooms(text) {
  if (!text) return null;
  // "сан узел" is often written with a space, so the stem allows one.
  const m =
    text.match(/(\d)\s*(?:сан\s?узл|с\/?у\b|ванн[аы]|bathroom|sanuzel|hammom)/i) ||
    text.match(/(?:сан\s?узл[а-яё]*|bathrooms?|sanuzel|hammom)\D{0,4}(\d)/i);
  const n = m ? Number(m[1]) : null;
  return n != null && n >= 1 && n <= 5 ? n : null;
}

// Whether communal/utility payments are billed separately from rent (UZ note:
// when nothing is stated, utilities are usually *included* — the UI renders
// null accordingly). Returns true (separate) / false (included) / null.
export function parseCommunalSeparated(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  // NB: \w does not match Cyrillic in JS regex, so stems use [а-яё]*.
  if (/(коммунал[а-яё]*(?:\s+услуг[а-яё]*)?\s*(?:отдельно|сверху|плюс|оплачива[а-яё]*\s*отдельно)|свет\s*вода\s*газ\s*отдельно|kommunal\w*\s*(?:alohida|ustiga)|utilities?\s*(?:separate|extra|not included))/i.test(t))
    return true;
  if (/(коммунал[а-яё]*(?:\s+услуг[а-яё]*)?\s*(?:включ|входит|в ?стоимост)|вс[её] ?включ|all ?inclusive|kommunal\w*\s*(?:kiritilgan|ichida)|ком+унал(?:каси)?\s+ичида|utilities?\s*included)/i.test(t))
    return false;
  return null;
}

// UZ/Central-Asian "kvartal" / massiv / micro-district, e.g. "Chilonzor 8
// kvartal", "Юнусабад 19 квартал", "мкр 4". Returns a short "N kvartal" label
// (used later to place the map pin more precisely), or null.
export function parseKvartal(text) {
  if (!text) return null;
  // Named Tashkent microdistricts are commonly written without an explicit
  // `микрорайон` label. Keep them in the same field as numbered kvartals so
  // they appear in the UI's "Quarter / microdistrict" row.
  if (/(?:^|[^\p{L}\p{N}_])(?:глинк[аи]?|glinka)(?:$|[^\p{L}\p{N}_])/iu.test(text)) return 'Glinka';
  const m =
    text.match(/(\d{1,3})\s*(?:-?\s*(?:chi|чи))?\s*[-\s]?\s*(?:квартал|кв-?л\b|kvartal(?:i)?|мкр\b|микрорайон|массив|massiv|daha(?:si|dan)?|hudud|худуд)/i) ||
    text.match(/(?:квартал|kvartal(?:i)?|мкр|микрорайон|массив|massiv|daha(?:si|dan)?|hudud|худуд)\s*[-№#]?\s*(\d{1,3})/i) ||
    // Tashkent shorthand omits the word "kvartal": "Chilonzor 12" means
    // Chilanzar district, 12th kvartal (not metro Chilonzor + building 12).
    text.match(/(?:чиланзар|chilonzor|chilanzar)\s*[-№#]?\s*(\d{1,2})(?!\d)/i);
  if (m) return `${m[1]} kvartal`;
  const centralBlock = text.match(/(?:^|[^\p{L}\p{N}_])(?:ц|c)\s*[-–]?\s*(\d{1,2})(?:$|[^\p{L}\p{N}_])/iu);
  return centralBlock ? `C-${centralBlock[1]}` : null;
}

// Features that do not have a dedicated normalized boolean are rendered in
// the UI's "Other amenities" row.
export function parseAmenities(text) {
  if (!text) return [];
  const amenities = [];
  if (/(?:посудомо|посудомийн|dishwasher|idish\s*yuvish|idishyuvg|ma[șs]ina de sp[ăa]lat vase)/i.test(text)) {
    amenities.push('Dishwasher');
  }
  if (/(?:комнат[а-яё]*\s+раздельн|изолированн[а-яё]*\s+комнат|separate\s+rooms?)/i.test(text)) {
    amenities.push('Separate rooms');
  }
  if (/(?:стиральн[а-яё]*\s+машин|washing\s+machine|kir\s*yuvish\s*mashin|kirmoshina)/i.test(text)) {
    amenities.push('Washing machine');
  }
  if (/(?:телевизор|телевизион|televizor|television|\btv\b)/i.test(text)) amenities.push('Television');
  if (/(?:постельн[а-яё]*\s+бель|bed\s*linen|toza\s+choyshab|yostiq\s+jild)/i.test(text)) amenities.push('Bed linen');
  if (/(?:полотенц|towels?|sochiq)/i.test(text)) amenities.push('Towels');
  return amenities;
}

// Named retail chains / malls mentioned (proximity signal). Deduped canonical
// names. Guards ("metro cash&carry" not the subway; "small" the shop).
const SHOP_CHAINS = [
  ['Korzinka', /korzinka|корзинка/i],
  ['Makro', /\bmakro\b|макро/i],
  ['Havas', /\b[хxh]avas\b|хавас/i],
  ['Carrefour', /carrefour|карфур/i],
  ['ATB', /\bатб\b|\batb\b/i],
  ['Klass', /\bklass\b|\bкласс\b/i],
  ['Magnum', /magnum|магнум/i],
  ['Bravo', /\bbravo\b|браво/i],
  ['Metro C&C', /\bmetro\s*(?:cash|c\s*&\s*c|market)|метро\s*кэш/i],
];
// Named civic/landmark places a post lists as orientation points ("рядом ЗАГС
// Чиланзарского района, рынок Катартал"). These are the "nearby landmarks" the
// LOCATIONS dictionary can't cover, because the names are local and open-ended.
// Each rule captures the following proper name when there is one, so the label
// stays informative ("Рынок Катартал") rather than a bare category.
const PLACE_KINDS = [
  ['Рынок', /(?:рынок|базар|bozor)\s+([A-ZА-ЯЁ][\wА-Яа-яЁё'’-]{2,24})/u],
  // No \b before Cyrillic: JS word boundaries only understand ASCII letters.
  ['ЗАГС', /(?:^|[^A-Za-zА-Яа-яЁё])ЗАГС(?:\s+([A-ZА-ЯЁ][\wА-Яа-яЁё'’-]{2,24}(?:\s+район[а-яё]*)?))?/u],
  ['Парк', /(?:парк)\s+([A-ZА-ЯЁ][\wА-Яа-яЁё'’-]{2,24})/u],
  ['Школа', /(?:школа)\s*(№\s*\d{1,4})/iu],
  ['Клиника', /(?:клиника|поликлиника|больница)\s+([A-ZА-ЯЁ][\wА-Яа-яЁё'’-]{2,24})/u],
  ['Стадион', /(?:стадион)\s+([A-ZА-ЯЁ][\wА-Яа-яЁё'’-]{2,24})/u],
  ['Университет', /(?:университет|институт)\s+([A-ZА-ЯЁ][\wА-Яа-яЁё'’-]{2,24})/u],
];

// Posts routinely spell out their surroundings — "Рядом есть: Миллий Бог,
// Ташкент сити, NRG U-Tower, Узбекфильм…" — and that list is worth more than
// the generic kinds below, which only ever recorded that *a* mosque exists.
const NEARBY_BLOCK_RE =
  /(?:^|\n)[^\n]{0,30}?(?:что\s+(?:есть|находится)\s+р[яa]дом|р[яa]дом(?:\s+(?:есть|находятся|расположены|с\s+домом))?|непода[лл][её]ку|поблизости|в\s+шаговой\s+доступности|окружени[ие]|ориентир(?:ы|ами)?|yaqinida|atrofida|yonida|nearby|landmarks?)\s*[:—-]?\s*([^\n]{4,500})/iu;

// Words that describe the flat rather than name a place, plus the filler that
// survives a comma split.
const NEARBY_NOISE_RE =
  /^(?:и|а|в|на|у|до|от|все|вс[её]|есть|рядом|близко|недалеко|минут\p{L}*|пешком|транспорт|остановк\p{L}*|магазин|магазины|аптека|аптеки|садик|садики|всё\s+необходимое|развит\p{L}*)$/iu;

// Phrases that promise surroundings without naming any: keep them out however
// they are worded ("вся инфраструктура города", "находится вся инфраструктура").
const NEARBY_FILLER_RE =
  /(?:инфраструктур\p{L}*|все\s+необходимо|вс[её]\s+рядом|шаговой\s+доступност|развитый\s+район)/iu;

/** Named places from an explicit "рядом" enumeration, in the order written. */
function enumeratedNearby(text) {
  // A post often carries both a short "Ориентир: X" line and a full
  // "Рядом есть: ..." list; the first match alone threw the longer one away.
  const blocks = [...text.matchAll(new RegExp(NEARBY_BLOCK_RE.source, NEARBY_BLOCK_RE.flags + 'g'))]
    .map((match) => match[1])
    .filter(Boolean);
  if (!blocks.length) return [];

  // Case-insensitive dedup: one post writes the same landmark both ways
  // ("Ориентир: Дружба Нородов" in the header, "Дружба нородов" in the list).
  const seen = new Set();
  const items = [];

  for (const item of blocks
    .join(', ')
    .split(/[,;•·|]+/)
    .map((part) =>
      part
        .replace(/\s{2,}/g, ' ')
        .replace(/^[\s\-–—.]+|[\s\-–—.!]+$/g, '')
        .trim(),
    )) {
    if (item.length < 3 || item.length > 45) continue;
    if (NEARBY_NOISE_RE.test(item) || NEARBY_FILLER_RE.test(item)) continue;
    // Needs at least one real word; "5 мин" and "2" are not places.
    if (!/\p{L}{3,}/u.test(item)) continue;

    const key = item.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    items.push(item);
    if (items.length >= 14) break;
  }

  return items;
}

export function parseNearbyPlaces(text) {
  if (!text) return [];
  const out = enumeratedNearby(text);
  for (const [kind, re] of PLACE_KINDS) {
    const m = text.match(re);
    if (!m) continue;
    const label = m[1] ? `${kind} ${m[1].trim()}` : kind;
    // A generic "Мечеть" adds nothing when the post already named one.
    if (out.some((item) => item.toLowerCase().includes(kind.toLowerCase()))) continue;
    if (!out.includes(label)) out.push(label);
  }
  return out.slice(0, 16);
}

export function parseNearbyShops(text) {
  if (!text) return [];
  const out = [];
  for (const [name, re] of SHOP_CHAINS) if (re.test(text) && !out.includes(name)) out.push(name);
  // Named malls: "High Town Mall", "Compass Mall", "Samarqand moll". Name words
  // are Latin (mall brands almost always are), so we don't trip over Cyrillic
  // word boundaries (JS \w skips Cyrillic).
  const named = text.match(/([A-Za-z][A-Za-z'’.&-]*(?:\s+[A-Za-z][A-Za-z'’.&-]*){0,3}\s+(?:mall|moll|молл))/i);
  if (named && !out.includes(named[1].trim())) out.push(named[1].trim());
  const trc = text.match(/(?:трц|тц)\s+([A-Za-z0-9'’.-]{2,25}|[А-Яа-яЁё0-9'’.-]{2,25})/i);
  if (trc) { const n = 'ТРЦ ' + trc[1].trim(); if (!out.includes(n)) out.push(n); }
  return out;
}

// --- More amenities / conditions (positive-only unless a negation is stated) ---
export function parseParking(text) {
  if (!text) return null;
  // "парков" stem covers парковка / парковочное место / парковки — the narrower
  // "парковк" missed "своё личное парковочное место".
  return /паркинг|парков|машино[- ]?мест|parking|avtoturargoh|mashina\s*joyi/i.test(text) ? true : null;
}
export function parseElevator(text) {
  if (!text) return null;
  if (/без\s*лифт|no\s*elevator|lift\s*yo['’]?q/i.test(text)) return false;
  return /лифт|elevator|\blift\b/i.test(text) ? true : null;
}
export function parseHeating(text) {
  if (!text) return null;
  return /отоплени|heating|otoplenie|isitish|markaziy\s*issiq/i.test(text) ? true : null;
}
export function parseHotWater(text) {
  if (!text) return null;
  return /горяч[а-яё]*\s*вод|hot\s*water|issiq\s*suv/i.test(text) ? true : null;
}
export function parseInternet(text) {
  if (!text) return null;
  return /интернет|wi[- ]?fi|wifi|\binternet\b/i.test(text) ? true : null;
}
export function parseSmoking(text) {
  if (!text) return null;
  if (/нельзя\s*курить|курить\s*нельзя|без\s*курени|не\s*курить|курить\s*запрещ|курение\s*запрещ|no\s*smoking/i.test(text)) return false;
  if (/можно\s*курить|курить\s*можно|smoking\s*allowed/i.test(text)) return true;
  return null;
}
export function parseNegotiable(text) {
  if (!text) return null;
  if (/без\s*торга|торг\s*не\s*уместен|цена\s*фиксир|fixed\s*price|торга\s*нет/i.test(text)) return false;
  if (/возможен\s*торг|торг\s*уместен|торг\s*есть|торгу[еюё]|договорн(?:ая|ой)|kelishamiz|kelishilg|price\s*negotiable/i.test(text)) return true;
  return null;
}
