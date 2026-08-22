from pathlib import Path

path = Path('backend/src/db.js')
text = path.read_text()
start = text.index('export async function initDb() {')
end = text.index('\nconst UPSERT_SQL = `', start)
old = text[start:end]
if "const client = await pool.connect();" in old:
    raise SystemExit('initDb is already serialized')

body = old.replace('export async function initDb() {\n', '', 1)
body = body.rsplit('\n}', 1)[0]
body = body.replace('await pool.query(', 'await client.query(')

new = '''export async function initDb() {
    const client = await pool.connect();

    try {
        // Backend and queue-task-api start at the same time in production. PostgreSQL
        // can race even on CREATE TABLE IF NOT EXISTS because both sessions may try
        // to create the same catalog type concurrently. Serialize only schema DDL;
        // normal reads/writes never take this lock.
        await client.query(
            'SELECT pg_advisory_lock($1)',
            [742_000],
        );

''' + body + '''
    } finally {
        try {
            await client.query(
                'SELECT pg_advisory_unlock($1)',
                [742_000],
            );
        } finally {
            client.release();
        }
    }
}'''

path.write_text(text[:start] + new + text[end:])
