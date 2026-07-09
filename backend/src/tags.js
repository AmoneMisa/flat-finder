// Derives human-friendly tags for a listing card from its title + description.
// Keyword patterns cover EN / RO / RU / UA so tags work across all portals.

// Keyword patterns cover EN / RO / RU / UA / UZ / KZ so tags work across every
// portal, including Uzbek (Latin) and Kazakh (Cyrillic) posts.
const KEYWORD_TAGS = [
  ['furnished', /\b(furnished|mobilat|mebl|меблюванн|мебльован|с мебелью|обставлен|jihozlangan|jihozli|жиһаз)/i],
  ['unfurnished', /\b(unfurnished|nemobilat|без мебел|без меблів|jihozsiz|жиһazsіz|жиһазсыз)/i],
  ['renovated', /\b(renovat|euro ?renov|євроремонт|ремонт|отремонт|reamenajat|с ремонтом|ta'?mirlangan|remont|жөндел|жөндеу)/i],
  ['new build', /\b(new build|bloc nou|constructie noua|новострой|новобуд|новостро|yangi qurilgan|novostroyka|жаңа құрыл)/i],
  ['parking', /\b(parking|parcare|garaj|garage|гараж|парков|парко-?місц|avtoturargoh|avtomobil joyi|автотұрақ|көлік)/i],
  ['balcony', /\b(balcony|balcon|балкон|лоджи|лоджі|balkon|балкон)/i],
  ['elevator', /\b(elevator|lift|ліфт|лифт|lift|лифт)/i],
  ['pets ok', /\b(pets? ?(allowed|ok)|se accepta animale|можно с животными|з тваринами|uy hayvon|жануар)/i],
  ['no agency', /\b(no agency|fara intermediari|fără comision|без посредник|без агент|собственник|власник|від власника|vositachisiz|egasidan|иесінен)/i],
  ['utilities included', /\b(utilities included|utilitati incluse|комунальні включ|коммунальн.*включ|kommunal)/i],
  ['studio', /\b(studio|garsonier|студи[яї]|studiya)/i],
  ['central heating', /\b(central heating|centrala termica|central[ăa]|центральн.*отопл|опаленн|isitish|жылу)/i],
  ['pool', /\b(pool|piscina|бассейн|басейн|basseyn)/i],
  ['negotiable', /\b(negotiable|negociabil|торг(?! центр)|можен торг|kelishilgan|kelishamiz|келісім)/i],
  ['for rent', /\b(for rent|de inchiriat|inchiriere|оренда|аренда|сдам|сдаётся|здам|ijara|arenda|жалға)/i],
  ['for sale', /\b(for sale|de vanzare|vanzare|продаж|продажа|продам|продаётся|sotiladi|sotuv|сатылады)/i],
];

const DEAL_TAGS = { sale: 'for sale', longRent: 'long-term rent', shortRent: 'short-term rent' };
const AUDIENCE_TAGS = { women: 'girls only', men: 'men only', family: 'family' };

export function extractTags({
  title = '',
  description = '',
  propertyType,
  byAgency,
  rooms,
  dealType,
  audience,
}) {
  const text = `${title} ${description}`.toLowerCase();
  const tags = [];

  if (rooms) tags.push(`${rooms} rooms`);
  if (dealType && DEAL_TAGS[dealType]) tags.push(DEAL_TAGS[dealType]);
  if (audience && AUDIENCE_TAGS[audience]) tags.push(AUDIENCE_TAGS[audience]);
  tags.push(byAgency ? 'agency' : 'owner');

  for (const [tag, re] of KEYWORD_TAGS) {
    if (re.test(text)) tags.push(tag);
  }

  // De-duplicate while preserving order, cap to keep cards tidy.
  return [...new Set(tags)].slice(0, 8);
}
