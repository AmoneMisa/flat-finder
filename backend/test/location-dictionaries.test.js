import test from 'node:test';
import assert from 'node:assert/strict';
import { matchDictionaryLocation } from '../src/location-dictionaries.js';

const cases = [
  ['Квартира Юнусабад 19, рядом метро', 'UZ', 'Tashkent', 'microdistricts', 'Yunusabad-19'],
  ['ЖК Хон Сарой, Ташкент', 'UZ', 'Tashkent', 'residentialComplexes', 'Xon Saroy'],
  ['Buyuk Ipak Yo‘li metro', 'UZ', 'Tashkent', 'metro', 'Buyuk Ipak Yoli'],
  ['Согдиана, Самарканд', 'UZ', 'Samarkand', 'microdistricts', 'Sogdiana'],
  ['Самал 2, Алматы', 'KZ', 'Almaty', 'microdistricts', 'Samal-2'],
  ['метро Жібек жолы', 'KZ', 'Almaty', 'metro', 'Zhibek Zholy'],
  ['Хайвилл, Астана', 'KZ', 'Astana', 'residentialComplexes', 'Highvill'],
  ['Сарайшық ауданы', 'KZ', 'Astana', 'districts', 'Saraishyk'],
  ['Piața Victoriei, București', 'RO', 'Bucharest', 'metro', 'Piata Victoriei'],
  ['apartament Coresi Avantgarden Brașov', 'RO', 'Brasov', 'residentialComplexes', 'Coresi Avantgarden'],
  ['оренда на Троєщині', 'UA', 'Kyiv', 'microdistricts', 'Troyeshchyna'],
  ['Новопечерские Липки', 'UA', 'Kyiv', 'residentialComplexes', 'Novopecherski Lypky'],
  ['Салтівський район Харків', 'UA', 'Kharkiv', 'districts', 'Saltivskyi'],
  ['метро Олексіївська', 'UA', 'Kharkiv', 'metro', 'Oleksiivska'],
  ['квартира в Аркадии', 'UA', 'Odesa', 'microdistricts', 'Arkadia'],
  ['Сихів, Львів', 'UA', 'Lviv', 'microdistricts', 'Sykhiv'],
];

for (const [text, country, city, type, name] of cases) {
  test(`${country}/${city}: ${text}`, () => {
    const result = matchDictionaryLocation(text, country, city);
    assert.ok(result);
    assert.equal(result.type, type);
    assert.equal(result.name, name);
  });
}

test('does not substring-match short aliases inside unrelated words', () => {
  assert.equal(matchDictionaryLocation('ordinary apartment description', 'KZ', 'Astana'), null);
});
