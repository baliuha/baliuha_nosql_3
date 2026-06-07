// 1. Find all Thriller movies with an average rating above 4.0
MATCH (g:Genre {name: "Thriller"})<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-()
WITH m, avg(r.rating) AS avgRating
WHERE avgRating > 4.0
RETURN m.movieId AS movieId, m.title AS title, avgRating
ORDER BY avgRating DESC;

// 2. Find users who gave a 5-star rating to more than 50 movies
MATCH (u:User)-[r:RATED]->(:Movie)
WHERE r.rating = 5
WITH u, count(r) AS fiveStarCount
WHERE fiveStarCount > 50
RETURN u.userId AS userId, fiveStarCount
ORDER BY fiveStarCount DESC;

// 3. Find movies highly rated (rating >= 4) by both userId=1 and userId=2
MATCH (u1:User {userId: 1})-[r1:RATED]->(m:Movie)<-[r2:RATED]-(u2:User {userId: 2})
WHERE r1.rating >= 4 AND r2.rating >= 4
RETURN m.movieId AS movieId, m.title AS title, r1.rating AS user1Rating, r2.rating AS user2Rating;

// 4. Find genres whose movies consistently get high ratings
MATCH (g:Genre)<-[:HAS_GENRE]-(m:Movie)<-[r:RATED]-()
WITH g, avg(r.rating) AS avgRating, count(r) AS totalRatings
RETURN g.name AS genre, avgRating, totalRatings
ORDER BY avgRating DESC;

// 5. Collaborative Filtering Recommendation ("Users with similar tastes also watched")
MATCH (u:User {userId: 1})-[r1:RATED]->(m1:Movie)<-[r2:RATED]-(sim:User)
WHERE r1.rating >= 4 AND r2.rating >= 4 AND sim <> u
WITH u, sim, count(m1) AS commonLikes
WHERE commonLikes >= 5 // Users who share at least 5 highly-rated movies
MATCH (sim)-[r3:RATED]->(recMovie:Movie)
WHERE r3.rating >= 4 AND NOT (u)-[:RATED]->(recMovie)
RETURN recMovie.movieId AS movieId, recMovie.title AS title, avg(r3.rating) AS avgSimRating, count(sim) AS recommendedByCount
ORDER BY recommendedByCount DESC, avgSimRating DESC
LIMIT 10;

// 6. Find the shortest path between two users via shared movies
MATCH (u1:User {userId: 1}), (u2:User {userId: 2})
MATCH p = shortestPath((u1)-[:RATED*]-(u2))
RETURN p;