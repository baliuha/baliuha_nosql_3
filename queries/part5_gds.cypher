MATCH ()-[r:RATED]->() 
WITH r LIMIT 60000 
DELETE r;

// ------------------------------------------
// 5.1. PageRank on Movie Graph
// ------------------------------------------

// Крок 1: матеріалізуємо ребра фільм-фільм через спільних користувачів
MATCH (m1:Movie)<-[r1:RATED]-(u:User)-[r2:RATED]->(m2:Movie)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(m1) < id(m2)
WITH m1, m2, count(u) AS weight
WHERE COUNT { (m1)<-[:RATED]-() } > 20
  AND COUNT { (m2)<-[:RATED]-() } > 20
WITH m1, m2, weight
ORDER BY weight DESC
LIMIT 30000
MERGE (m1)-[co:CO_RATED]-(m2)
SET co.weight = weight;

// Крок 2: створюємо проєкцію на основі матеріалізованих ребер
CALL gds.graph.project(
  'movieGraph',
  'Movie',
  { CO_RATED: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: PageRank
CALL gds.pageRank.stream('movieGraph', {
  maxIterations: 20,
  dampingFactor: 0.85,
  relationshipWeightProperty: 'weight'
})
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).title AS movieTitle, score
ORDER BY score DESC, movieTitle ASC
LIMIT 10;

// Крок 4: видаляємо проєкцію та тимчасові ребра
CALL gds.graph.drop('movieGraph');
MATCH ()-[co:CO_RATED]-() DELETE co;

// ------------------------------------------
// 5.2. Community Detection (Louvain)
// ------------------------------------------

// Крок 1: Матеріалізуємо ребра користувач-користувач через спільні фільми
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(u1) < id(u2)
WITH u1, u2, count(m) AS weight
ORDER BY weight DESC
LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

// Крок 2: Створюємо проєкцію
CALL gds.graph.project(
  'userSimilarity',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Запускаємо Louvain та ЗАПИСУЄМО результати у вузли (writeProperty)
// Це дозволить нам потім робити звичайні MATCH запити по кластерах
CALL gds.louvain.write('userSimilarity', {
  relationshipWeightProperty: 'weight',
  writeProperty: 'communityId'
})
YIELD communityCount, modularity;

// Крок 4a: Аналіз розмірів кластерів (Виводимо 10 найбільших)
MATCH (u:User)
WHERE u.communityId IS NOT NULL
RETURN u.communityId AS community, count(u) AS size
ORDER BY size DESC
LIMIT 10;

// Крок 4b: Топ-3 жанри для кожного з 10 найбільших кластерів
// Знаходимо кластери, потім дивимося, які жанри фільмів з оцінкою >= 4 переважають
MATCH (u:User)
WHERE u.communityId IS NOT NULL
WITH u.communityId AS community, count(u) AS clusterSize
ORDER BY clusterSize DESC
LIMIT 10
MATCH (u:User {communityId: community})-[r:RATED]->(m:Movie)-[:HAS_GENRE]->(g:Genre)
WHERE r.rating >= 4
WITH community, clusterSize, g.name AS genre, count(r) AS genreCount
ORDER BY clusterSize DESC, genreCount DESC
WITH community, clusterSize, collect(genre)[0..3] AS topGenres
RETURN community, clusterSize, topGenres
ORDER BY clusterSize DESC;

// Крок 5: Видаляємо проєкцію, тимчасові ребра та очищаємо властивості вузлів
CALL gds.graph.drop('userSimilarity');
MATCH ()-[sim:SIMILAR]-() DELETE sim;
MATCH (u:User) REMOVE u.communityId;

// ------------------------------------------
// 5.3. Shortest Path Between Users (Dijkstra)
// ------------------------------------------

// Проєкція потрібна та сама, що і для Louvain — пересотворіть, якщо видалили
MATCH (u1:User)-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND id(u1) < id(u2)
WITH u1, u2, count(m) AS weight
WITH u1, u2, weight
ORDER BY weight DESC
LIMIT 50000
MERGE (u1)-[sim:SIMILAR]-(u2)
SET sim.weight = weight;

CALL gds.graph.project(
  'userGraph',
  'User',
  { SIMILAR: { orientation: 'UNDIRECTED', properties: 'weight' } }
)
YIELD graphName, nodeCount, relationshipCount;

// Крок 3: Запуск алгоритму Дейкстри для першої пари користувачів (1 та 100)
// Шукаємо найкоротший шлях за кількістю кроків (degrees of separation)
MATCH (source:User {userId: 1}), (target:User {userId: 100})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target
})
YIELD totalCost, nodeIds
RETURN 
  totalCost AS pathLength, 
  [nodeId IN nodeIds | gds.util.asNode(nodeId).userId] AS pathUserIds;

// Крок 4: Запуск для іншої більш віддаленої пари (50 та 500)
MATCH (source:User {userId: 50}), (target:User {userId: 500})
CALL gds.shortestPath.dijkstra.stream('userGraph', {
  sourceNode: source,
  targetNode: target
})
YIELD totalCost, nodeIds
RETURN 
  totalCost AS pathLength, 
  [nodeId IN nodeIds | gds.util.asNode(nodeId).userId] AS pathUserIds;

// Крок 5: Видаляємо проєкцію та тимчасові ребра
CALL gds.graph.drop('userGraph');
MATCH ()-[sim:SIMILAR]-() DELETE sim;