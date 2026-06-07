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
The ratings.csv file contains a massive number of rows. Attempting to load all of these relationships in a single standard transaction would likely crash the database. To solve this, `apoc.periodic.iterate` is used to break the job down into smaller batches of 10,000 rows.
We use MATCH to find the existing User and Movie nodes (which is fast due to indexes), and then MERGE the relationship to prevent duplicate edge upon multiple script runs.
To avoid locking collisions and deadlocks, `parallel: true` option is used.

