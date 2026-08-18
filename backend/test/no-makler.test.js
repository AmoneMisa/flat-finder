import test from 'node:test';
import assert from 'node:assert/strict';

import { makeListing } from '../src/normalize.js';
import { classifyAgency } from '../src/textparse.js';
import { parseCommission } from '../src/textparse-overrides.js';

const text = `Квартира ЖК NRG BAXT БЕЗ МАКЛЕР!\n\nСдается квартира порядочным людям и иностранцам со всеми удобствами.`;

test('no-makler listing has no commission and clean residential-complex name', () => {
  const listing = makeListing({
    id: 'nrg-baxt-no-makler',
    source: 'olx',
    country: 'UZ',
    title: 'Квартира ЖК NRG BAXT',
    description: 'БЕЗ МАКЛЕР!\nСдается квартира порядочным людям и иностранцам со всеми удобствами.',
    byAgency: classifyAgency(text),
  });

  assert.equal(listing.byAgency, false);
  assert.equal(listing.commission, false);
  assert.equal(listing.commissionPercent, 0);
  assert.equal(listing.residenceComplex, 'NRG BAXT');
});

test('multilingual no-commission phrases override broker words', () => {
  const samples = [
    'Без риелтора, без комиссии',
    'Без посредников, от собственника',
    'No broker fee, owner direct',
    'Fără comision, direct proprietar',
    'Maklersiz, uy egasidan',
    'Komissiyasiz, vositachisiz',
    'Комиссиясыз, үй иесінен',
    'Делдалсыз',
  ];

  for (const sample of samples) {
    assert.deepEqual(parseCommission(sample), { has: false, percent: 0 }, sample);
  }
});

test('explicit commission percentage is parsed across languages', () => {
  const samples = [
    ['Комиссия 50%', 50],
    ['Комісія 40%', 40],
    ['Commission 25%', 25],
    ['Comision 30%', 30],
    ['Komissiya 35%', 35],
    ['Makler 50%', 50],
    ['M50%', 50],
    ['Делдал 20%', 20],
  ];

  for (const [sample, percent] of samples) {
    assert.deepEqual(parseCommission(sample), { has: true, percent }, sample);
  }
});

test('broker mention alone does not imply commission', () => {
  const samples = [
    'Показывает риелтор',
    'Makler bilan aloqa',
    'Contact agent for viewing',
    'Agenție imobiliară',
    'Vositachi orqali ko‘rish mumkin',
    'Делдал көрсетеді',
  ];

  for (const sample of samples) {
    assert.deepEqual(parseCommission(sample), { has: null, percent: null }, sample);
  }
});
