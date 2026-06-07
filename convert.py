import csv
from pathlib import Path

DATA_DIR = Path('data')
IMPORT_DIR = Path('import')
IMPORT_DIR.mkdir(exist_ok=True)

# movies.dat: MovieID::Title::Genres
with open(DATA_DIR / 'movies.dat', encoding='latin-1') as f_in, open(IMPORT_DIR / 'movies.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['movieId', 'title', 'genres'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts)

# ratings.dat: UserID::MovieID::Rating::Timestamp
with open(DATA_DIR / 'ratings.dat', encoding='latin-1') as f_in, open(IMPORT_DIR / 'ratings.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['userId', 'movieId', 'rating', 'timestamp'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts)

# users.dat: UserID::Gender::Age::Occupation::Zip
with open(DATA_DIR / 'users.dat', encoding='latin-1') as f_in, open(IMPORT_DIR / 'users.csv', 'w', newline='', encoding='utf-8') as f_out:
    writer = csv.writer(f_out)
    writer.writerow(['userId', 'gender', 'age', 'occupation'])
    for line in f_in:
        parts = line.strip().split('::')
        writer.writerow(parts[:4])  # zip не потрібен
