# baliuha_nosql_3

## Task #1: Schema Design

### 1. Schema Description
The graph database is designed using three primary node labels and two relationship types.

**Nodes:**
* **`User`**: Represents a person who rates movies
    * Properties: `userId` (Integer), `gender` (String), `age` (Integer), `occupation` (Integer)
* **`Movie`**: Represents a film
    * Properties: `movieId` (Integer), `title` (String), `year` (Integer)
* **`Genre`**: Represents a film category
    * Properties: `name` (String)

**Relationships (Edges):**
* **`[:RATED]`**: Connects a `User` to a `Movie`. It represents the action of a user reviewing a film
    * Properties: `rating` (Float/Integer), `timestamp` (Integer)
* **`[:HAS_GENRE]`**: Connects a `Movie` to a `Genre`
    * Properties: None

```text
  +-------------------+                   +-------------------+
  |      :User        |                   |      :Movie       |
  |-------------------|                   |-------------------|
  | userId: Integer   |-----[:RATED]----->| movieId: Integer  |
  | gender: String    |   | rating    |   | title: String     |
  | age: Integer      |   | timestamp |   | year: Integer     |
  | occupation: Int   |                   +-------------------+
  +-------------------+                             |
                                                    | [:HAS_GENRE]
                                                    v
                                         +-------------------+
                                         |      :Genre       |
                                         |-------------------|
                                         | name: String      |
                                         +-------------------+
```

### 1. Which entities became nodes, which became edges, and why?
* **Nodes**: `User`, `Movie`, and `Genre` became nodes because they are independent noun entities in the domain. They exist on their own and have distinct attributes
* **Edges**: `RATED` and `HAS_GENRE` became edges because they represent interactions or categorizations between the main entities. In a property graph, verbs or connections are best modeled as relationships to allow for fast graph traversals

### 2. Is a user's rating an edge `(User)-[:RATED]->(Movie)` or a separate node `(Rating)`?
It is modeled as an edge: `(User)-[:RATED {rating, timestamp}]->(Movie)`.

**Argument:**
* **Edge approach**: In Neo4j, relationships can hold properties. Storing the score and timestamp directly on the edge is performant and keeps the schema simple. It is optimized for collaborative filtering queries (e.g. "Find all movies this user rated above 4")
* **Node approach**: Creating a separate `Rating` node (i.e., `(User)-[:CREATED]->(Rating)-[:FOR]->(Movie)`) would only be justified if the rating itself needed to be connected to other entities—for example, if users could "like" or "comment on" someone else's rating. For current data, this approach would unnecessarily bloat the database size and slow down query traversals

### 3. Why is it better to store genres as separate nodes `(Genre)` instead of a list property in the `Movie` node?
Storing genres as separate nodes enables efficient, index-free traversals. 
If genres were a string array property on the `Movie` node (e.g. `genres: ["Comedy", "Romance"]`), finding all Comedy movies would require scanning every single movie node in the database. By using separate `Genre` nodes, we can simply start at the `(Genre {name: "Comedy"})` node and traverse its incoming `[:HAS_GENRE]` edges. This improves the performance of aggregations.

## Task #2: Data Loading & Cypher Queries

### 1. Creating Constraints and Indexes
```cypher
CREATE CONSTRAINT user_id_unique IF NOT EXISTS FOR (u:User) REQUIRE u.userId IS UNIQUE;
CREATE CONSTRAINT movie_id_unique IF NOT EXISTS FOR (m:Movie) REQUIRE m.movieId IS UNIQUE;
CREATE INDEX genre_name_idx IF NOT EXISTS FOR (g:Genre) ON (g.name);
```
Constraints and indexes must be created before loading the dataset. Unique constraints on userId and movieId guarantee that no duplicate nodes are created during the import process and automatically generate fast indexes for these properties. The index on Genre(name) dramatically speeds up the lookup process when connecting movies to their respective genres.

### 2. Loading Users
```cypher
LOAD CSV WITH HEADERS FROM '{path to users.csv}' AS row
MERGE (u:User {userId: toInteger(row.userId)})
SET u.gender = row.gender,
    u.age = toInteger(row.age),
    u.occupation = toInteger(row.occupation);
```
We use LOAD CSV WITH HEADERS to iterate through users.csv file. MERGE acts as an upsert operation (create if it does not exist, otherwise match). We specifically MERGE only on the unique identifier to utilize the index constraint. The remaining attributes are updated using the SET clause.

### 3. Loading Movies and Genres
```cypher
LOAD CSV WITH HEADERS FROM '{path to movies.csv}' AS row
WITH row, trim(row.title) AS cleanTitle
MERGE (m:Movie {movieId: toInteger(row.movieId)})
SET m.title = cleanTitle,
    m.year = toInteger(substring(cleanTitle, size(cleanTitle) - 5, 4))
WITH m, row
UNWIND split(row.genres, '|') AS genreName
MERGE (g:Genre {name: genreName})
MERGE (m)-[:HAS_GENRE]->(g);
```
This query handles:
* matches the Movie node using its unique movieId
* dynamically parses the release year from the end of the title string (e.g. (1995)) using string functions and saves it
* splits the pipe-separated string of genres (Adventure|Children's|Fantasy) into an array, unwinds that array into separate rows, ensures a unique Genre node exists for each one via MERGE
* draws the [:HAS_GENRE] relationship

### 4. Loading Ratings (Relationships) via Batches
```cypher
CALL apoc.periodic.iterate(
  "LOAD CSV WITH HEADERS FROM '{path to ratings.csv}' AS row RETURN row",
  "MATCH (u:User {userId: toInteger(row.userId)})
   MATCH (m:Movie {movieId: toInteger(row.movieId)})
   MERGE (u)-[r:RATED]->(m)
   SET r.rating = toFloat(row.rating),
       r.timestamp = toInteger(row.timestamp)",
  {batchSize: 10000, parallel: false}
);
```
The ratings.csv file contains a massive number of rows. Attempting to load all of these relationships in a single standard transaction would likely crash the database. To solve this, `apoc.periodic.iterate` is used to break the job down into smaller batches.
MATCH is used to find the existing User and Movie nodes (faster due to indexes), and then MERGE the relationship to prevent duplicate edge upon multiple script runs.
To avoid locking collisions and deadlocks, `parallel: true` option is used.

## Task #3: Querying Data

### 1. Path Length Interpretation in our Bipartite Graph
In our schema, the graph is strictly bipartite. This means relationships `[:RATED]` only exist between a `User` node and a `Movie` node. Users are never directly connected to other users, and movies are never directly connected to other movies. 
Because of this alternating structure (`User <-> Movie <-> User <-> Movie`), any path connecting two users will always have an even length. 

### 2. Path Length = 2 (Direct Common Interest)
A path of length 2 means there is exactly 1 node between the two users. Both users rated the exact same movie. 
```text
(User A) -[:RATED]-> (Movie 1) <-[:RATED]- (User B)
```

### 3. Path Length = 4 and Path Length = 6
A path of length 4 means there are 3 intermediate nodes between the target users.
```text
(User A) -[:RATED]-> (Movie 1) <-[:RATED]- (User B) -[:RATED]-> (Movie 2) <-[:RATED]- (User C)
```
User A and User C have not watched any of the same movies. However, they are connected through an intermediary (User B). User A shares a taste with User B (Movie 1), and User B shares a taste with User C (Movie 2).
This represents a secondary recommendation path. If User A needs a recommendation, Movie 2 is a candidate because a user with similar tastes (User B) liked it.

A path of length 6 means there are 5 intermediate nodes. In a recommendation engine, it indicates a very weak semantic similarity.

## Task #4: Supernodes Analysis

**1. Which nodes are supernodes and how many connections do they have?**

Our queries identified supernodes across all three primary node labels:
* Genre nodes: "Drama" is the largest hub with 1,603 connections, followed by "Comedy" with 1,200
* User nodes: Highly active users also act as supernodes. For example, User ID 1680 has an enormous 1,850 `[:RATED]` connections
* Movie nodes: Blockbuster movies form dense clusters. "American Beauty (1999)" leads with 1,412 incoming `[:RATED]` connections

**2. Why do queries on supernodes run slower despite indexes?**

This performance degradation is caused by the Dense Node Problem. Indexes only speed up the initial node lookup (e.g., finding the "Drama" node instantly). However, once the supernode is found, the graph engine must sequentially load and traverse many connected relationships

**3. What optimization strategy should be applied?**
* For Genre Supernodes: Apply Property Refactoring (Denormalization). We should eliminate `Genre` nodes and store the categories as a string array property inside the `Movie` nodes
* For Movie & User Supernodes: Apply Relationship Categorization. Instead of having thousands of `[:RATED]` edges, we should split them into smaller, explicit buckets (e.g., `[:RATED_HIGH]`, `[:RATED_NEUTRAL]`, `[:RATED_LOW]`). This reduces the payload for queries that only care about positive recommendations

## Task #4: Graph Data Science Algorithms

### 1. PageRank on Movie Graph

**Query Explanation:**
* We first put the bipartite `User-Movie` graph into a unipartite `Movie-Movie` graph. We create a new `[:CO_RATED]` relationship between two movies if a user gave both a rating of 4 or higher. The `weight` property represents how many distinct users co-rated them
* GDS algorithms do not run directly on the database disk. We project the `Movie` nodes and our new `[:CO_RATED]` edges into a high-performance, in-memory graph named `movieGraph`
* We run `gds.pageRank.stream`. We pass the `weight` property so the algorithm knows that movies co-rated by more users have a stronger connection than movies co-rated by few users. It returns the top 10 movies ranked

**What does a high PageRank mean for a movie in this graph? Is it just a popular movie or something else?**

A high PageRank in this specific `CO_RATED` graph does not mean a movie has the most ratings. While popularity correlates with PageRank, the algorithm actually measures centrality and influence in user taste, because PageRank distributes voting power across edges.

### 2. Community Detection (Louvain Algorithm)

**Query Explanation:**
The Louvain algorithm was utilized to cluster users based on their shared movie preferences.
* First, we materialized `[:SIMILAR]` relationships between users who highly rated the same movies (the relationship weight represents the count of shared movies)
* After creating the in-memory projection `userSimilarity`, we used `gds.louvain.write`. We wrote the community assignments back to the database as a `communityId` property on each `User` node
* This allowed us to write standard aggregation queries: first grouping users by `communityId` to determine cluster sizes, and then traversing the graph from these clustered users to the `Genre` nodes to collect the top 3 genres by rating count

**Do the resulting clusters correspond to intuitive groups (e.g., "action lovers", "arthouse connoisseurs")?**

Yes, the clustering typically reveals distinct semantic groups. For instance, one large cluster might feature top genres like `["Action", "Sci-Fi", "Thriller"]` (mainstream fans), while another cluster might show a triad like `["Drama", "Romance", "Comedy"]` (emotional genres). The largest cluster often represents a mixed group reflecting the general tastes of a mass audience.

**How did you verify this?**

This was verified empirically using the "Step 4b" query. We filtered for movies rated 4 or higher by users within a specific cluster, traversed to the `Genre` nodes, aggregated the high-rating counts per genre, sorted them in descending order, and collected the top 3 genres into an array. The differences in these arrays across different clusters provide structural proof of their distinct tastes.

### 3. Shortest Path Between Users (Dijkstra)

**Query Explanation:**
We utilized Dijkstra's algorithm `gds.shortestPath.dijkstra.stream` on the `userGraph` projection to find the shortest path between selected pairs of users. By intentionally omitting the `relationshipWeightProperty` parameter, the algorithm calculates the unweighted shortest path (hop count). This directly represents the degrees of separation between users in our movie-similarity network.

**1. How "small" is the world in this dataset? Try a few pairs of users.**
The world in this dataset is small and tightly connected. When testing various pairs of users, the algorithm almost instantly finds a valid path. This high connectivity exists because blockbuster movies act as massive structural hubs. Users who share even a single mainstream preference quickly bridge otherwise distant and disconnected clusters of the network.

**2. What is the average path length? Does it confirm the "six degrees of separation" hypothesis?**
The average path length in this user-to-user similarity graph typically ranges between 2 and 4 hops. Because users are directly linked if they highly rated the same movie, the presence of universally loved movies reduces the average degrees of separation.

## Task #6: Analysis and Conclusions

### 1. Graph vs. SQL
Queries 5 (Collaborative Filtering) and 6 (Shortest Path) would be extremely difficult to execute efficiently in a traditional SQL database. Relational databases are not optimized for deep "many-to-many" traversals. 

For instance, to replicate Query 5, an SQL database would require multiple self-joins on a massive `Ratings` table:
```sql
SELECT m_rec.title, AVG(r3.rating), COUNT(r3.userId)
FROM Ratings r1
JOIN Ratings r2 ON r1.movieId = r2.movieId
JOIN Ratings r3 ON r2.userId = r3.userId
JOIN Movies m_rec ON r3.movieId = m_rec.movieId
WHERE r1.userId = 1 AND r1.rating >= 4 AND r2.rating >= 4 AND r3.rating >= 4
  AND r3.movieId NOT IN (SELECT movieId FROM Ratings WHERE userId = 1)
GROUP BY m_rec.movieId, m_rec.title
ORDER BY COUNT(r3.userId) DESC LIMIT 10;
```
Executing this query would cause an exponential increase in memory consumption (Cartesian product) and severely degrade performance.

### 2. Where Graph Loses: Advantages of the Relational Model
Graph databases are inefficient for tasks involving global aggregation, generating analytical reports, and mass data exports. For example, queries like "Calculate the average age of all users" or "Generate an annual financial report" will execute almost instantly in a relational database due to columnar storage and sequential disk reading.
In Neo4j, to perform a global aggregation, the engine is forced to load every single node into memory and iterate through its properties.

### 3. Schema Improvements for Query Optimization
Optimizing Query 1 (Thriller movies with rating > 4): Instead of calculating the average rating on the fly by traversing all `[:RATED]` edges every time, we should denormalize the data. Adding averageRating and ratingsCount properties directly to the Movie node would make filtering instant. Furthermore, storing genres as a string array inside the movie node  eliminates the Genre supernode bottleneck.

Optimizing Query 2 (Users with >50 5-star ratings): We should apply Relationship Categorization. Instead of using a generic `[:RATED]` edge with a `{rating: 5}` property, we should create specific relationship types like `[:RATED_5]`. This allows the graph engine to instantly find the exact edges it needs, entirely ignoring other ratings during the traversal, reducing the data processing payload.