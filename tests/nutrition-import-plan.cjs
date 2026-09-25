const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const test = require("node:test");
const path = require("node:path");

const source = fs.readFileSync(path.join(__dirname, "../dashboard.part11"), "utf8");
function section(from, to) {
  return source.slice(source.indexOf(from), source.indexOf(to, source.indexOf(from)));
}

const context = {
  nutritionMealSlots: [
    { key: "breakfast" }, { key: "lunch" }, { key: "snack" }, { key: "dinner" }
  ],
  nutritionWeekDates: () => ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"],
  recipeTotals: recipe => recipe.foods.reduce((sum, food) => ({
    kcal: sum.kcal + food[3], protein: sum.protein + food[4]
  }), { kcal: 0, protein: 0 })
};
vm.createContext(context);
vm.runInContext(
  section("function normalizeFoodKey(", "function parseAvoidFoods(") +
  section("function buildChatGPTPlanPrompt(", "function updateNutritionGeneratorMode("),
  context
);
const validate = context.validateNutritionImportPlan;
const parse = context.parseChatGPTPlanJSON;
const preferences = { calories: 3000, protein: 180, required: ["Reis"], avoided: ["Pilze"] };

function plan() {
  return {
    pairs: Array.from({ length: 4 }, (_, pair) => ({
      meals: context.nutritionMealSlots.map((slot, index) => ({
        slot: slot.key,
        name: "Gericht " + (pair + 1) + " " + (index + 1),
        ingredients: [
          { name: pair === 0 && index === 1 ? "Basmatireis" : "Zutat " + pair + " " + index + " A",
            amount: 180, unit: "g", kcal: 450, protein: 30, carbs: 60, fat: 10 },
          { name: "Zutat " + pair + " " + index + " B",
            amount: 120, unit: "g", kcal: 300, protein: 20, carbs: 25, fat: 12 }
        ]
      }))
    }))
  };
}

test("accepts four complete, varied blocks and keeps ingredient amounts for the app", () => {
  const result = validate(plan(), preferences);
  assert.equal(result.planned.length, 4);
  assert.equal(result.planned[0][1].foods[0][0], "Basmatireis");
  assert.equal(result.planned[0][1].foods[0][1], 180);
  assert.equal(result.planned[0][1].foods[0][2], "g");
  assert.equal(result.uniquePairStarts.length, 4);
});

test("copies concrete preferences into a prompt and accepts JSON inside a code block", () => {
  const prompt = context.buildChatGPTPlanPrompt({
    ...preferences, notes: "laktosefrei, keine Pilze", recentMeals: ["Puten-Reis-Bowl"]
  }, "2026-09-21");
  assert.match(prompt, /2026-09-21/);
  assert.match(prompt, /laktosefrei, keine Pilze/);
  assert.match(prompt, /Puten-Reis-Bowl/);
  assert.match(prompt, /genau vier Objekte in pairs/);
  const answer = parse("Hier ist dein Plan:\n```json\n" + JSON.stringify(plan()) + "\n```");
  assert.equal(validate(answer, preferences).planned.length, 4);
  assert.throws(() => parse("{ unvollständig"), /kein gültiges JSON/);
});

test("rejects excluded foods before replacing any meals", () => {
  const answer = plan();
  answer.pairs[2].meals[3].ingredients[1].name = "Champignonpilze";
  assert.throws(() => validate(answer, preferences), /ausgeschlossenes Lebensmittel/);
});

test("rejects missing required foods, repeated meals and incomplete responses", () => {
  const missing = plan();
  missing.pairs[0].meals[1].ingredients[0].name = "Couscous";
  assert.throws(() => validate(missing, preferences), /Wunschzutaten fehlen/);

  const duplicate = plan();
  duplicate.pairs[3].meals[2].name = duplicate.pairs[0].meals[0].name;
  assert.throws(() => validate(duplicate, preferences), /mehrfach/);
  assert.throws(() => validate({ pairs: [] }, preferences), /vier vollständige Blöcke/);
});

test("rejects implausible daily nutrition instead of persisting the response", () => {
  const answer = plan();
  answer.pairs[1].meals.forEach(meal => meal.ingredients.forEach(food => {
    food.kcal = 1;
    food.protein = 1;
  }));
  assert.throws(() => validate(answer, preferences), /Tagesblock/);
});
