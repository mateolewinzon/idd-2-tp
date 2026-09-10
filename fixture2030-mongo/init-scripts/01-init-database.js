// This script runs automatically only when MongoDB initializes a new volume.
const fixtureDb = db.getSiblingDB("fixture2030");

const collections = ["teams", "players"];

for (const collection of collections) {
  if (!fixtureDb.getCollectionNames().includes(collection)) {
    fixtureDb.createCollection(collection);
    print(`Created fixture2030.${collection}`);
  } else {
    print(`fixture2030.${collection} already exists`);
  }
}

db = db.getSiblingDB("fixture2030");

const teams = [
  // Grupo A
  "Mexico", "South Korea", "South Africa", "Czechia",
  // Grupo B
  "Canada", "Bosnia and Herzegovina", "Qatar", "Switzerland",
  // Grupo C
  "Brazil", "Morocco", "Haiti", "Scotland",
  // Grupo D
  "United States", "Paraguay", "Australia", "Turkey",
  // Grupo E
  "Germany", "Curacao", "Ivory Coast", "Ecuador",
  // Grupo F
  "Netherlands", "Japan", "Sweden", "Tunisia",
  // Grupo G
  "Belgium", "Egypt", "Iran", "New Zealand",
  // Grupo H
  "Spain", "Cape Verde", "Saudi Arabia", "Uruguay",
  // Grupo I
  "France", "Senegal", "Iraq", "Norway",
  // Grupo J
  "Argentina", "Algeria", "Austria", "Jordan",
  // Grupo K
  "Portugal", "DR Congo", "Uzbekistan", "Colombia",
  // Grupo L
  "England", "Croatia", "Ghana", "Panama",
];

const docs = teams.map((name) => ({ name }));

db.teams.deleteMany({});
const result = db.teams.insertMany(docs);

print(`Seed completo: ${Object.keys(result.insertedIds).length} equipos insertados en la coleccion "teams".`);
