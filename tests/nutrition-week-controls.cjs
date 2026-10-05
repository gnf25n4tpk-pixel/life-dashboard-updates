const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '../dashboard.part10'), 'utf8');
const section = (from, to) => source.slice(source.indexOf(from), source.indexOf(to, source.indexOf(from)));
const elements = new Map();
const context = {
  nutritionMealSlots: [{key:'breakfast'}, {key:'lunch'}, {key:'snack'}, {key:'dinner'}],
  nutritionToday: new Date(2026, 9, 5),
  selectedNutritionDate: new Date(2026, 9, 5),
  nutritionClone: value => JSON.parse(JSON.stringify(value)),
  emptyNutritionMeal: () => ({name:'', ingredients:[], persons:1}),
  makeIsoDate: date => `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`,
  startOfWeek: date => { const monday = new Date(date); monday.setDate(date.getDate() - ((date.getDay()+6)%7)); return monday; },
  loadNutritionData: () => ({days:{}, checkedShopping:{}, completedMeals:{}, individualDays:{}, disabledDays:{}}),
  localStorage: {setItem: () => {}},
  document: {getElementById: id => {if (!elements.has(id)) elements.set(id, {textContent:''}); return elements.get(id);}}
};
vm.createContext(context);
vm.runInContext(
  section('function nutritionPersons(', 'function renderNutritionToday()') +
  section('function shoppingKey(', 'function foodCategory(') +
  section('function buildShoppingByDay()', 'function shoppingItemHtml(') +
  section('function renderNutritionStats()', 'function renderNutrition()'),
  context
);
const run = code => vm.runInContext(code, context);
const iso = date => context.makeIsoDate(date);
const monday = new Date(2026, 9, 5);
const tuesday = new Date(2026, 9, 6);
const meal = (name, amount, persons = 1) => ({name, persons, ingredients:[{name, unit:'g', amount, kcal:amount, protein:amount/10, carbs:0, fat:0}]});

test('a disabled day is omitted without changing its paired day, including shopping and averages', () => {
  context.syncPairMeal(monday, 'lunch', meal('Reis', 100));
  assert.equal(context.buildShoppingList()[0].amount, 200);
  run(`nutritionData.disabledDays['2026-10-05'] = true`);
  assert.equal(context.dayTotals(monday).kcal, 0);
  assert.equal(context.dayTotals(tuesday).kcal, 100);
  assert.equal(context.buildShoppingList()[0].amount, 100);
  assert.equal(context.buildShoppingByDay()[0].items.length, 0);
  context.renderNutritionStats();
  assert.equal(elements.get('nutritionWeekAvgKcal').textContent, '100 kcal');
  assert.equal(elements.get('nutritionWeekMealsPlanned').textContent, '1 Mahlzeiten');
  run(`nutritionData.disabledDays['2026-10-05'] = false`);
});

test('zero persons exclude one meal only on the selected day and can be restored', () => {
  context.saveMealForSelectedContext(monday, 'lunch', meal('Reis', 100, 0));
  assert.equal(context.dayTotals(monday).kcal, 0);
  assert.equal(context.dayTotals(tuesday).kcal, 100);
  assert.equal(context.buildShoppingList()[0].amount, 100);
  context.saveMealForSelectedContext(monday, 'lunch', meal('Reis', 100, 1));
  assert.equal(context.buildShoppingList()[0].amount, 200);
});

test('selected week determines date range and shopping for a future plan', () => {
  run('selectedNutritionDate = new Date(2026, 9, 12)');
  assert.equal(iso(context.nutritionWeekDates()[0]), '2026-10-12');
  assert.equal(context.buildShoppingList().length, 0);
  context.syncPairMeal(new Date(2026,9,12), 'dinner', meal('Kartoffeln', 120));
  assert.equal(context.buildShoppingList()[0].amount, 240);
  run('selectedNutritionDate = new Date(2026, 9, 5)');
  assert.equal(context.buildShoppingList()[0].name, 'Reis');
});
