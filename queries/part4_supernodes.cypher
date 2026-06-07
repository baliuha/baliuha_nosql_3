// Find Top 5 Supernode Movies
MATCH (m:Movie)
RETURN m.title AS movieTitle, COUNT { (m)<-[:RATED]-() } AS degree
ORDER BY degree DESC LIMIT 5;

// Find Top 5 Supernode Genres
MATCH (g:Genre)
RETURN g.name AS genreName, COUNT { (g)<-[:HAS_GENRE]-() } AS degree
ORDER BY degree DESC LIMIT 5;

// Find Top 5 Supernode Users
MATCH (u:User)
RETURN u.userId AS userId, COUNT { (u)-[:RATED]->() } AS degree
ORDER BY degree DESC LIMIT 5;