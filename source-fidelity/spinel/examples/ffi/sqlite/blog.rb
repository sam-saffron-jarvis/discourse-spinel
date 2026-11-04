require_relative "sqlite3_lib"

# A toy blog: posts, tags (many-to-many), comments. Demonstrates
# create / insert / select with a few joins on top of the bare-metal
# Spinel SQLite FFI bindings.

class Blog
  def initialize(path)
    rc = SQL.sqlite3_open(path, SQL.db_out)
    if rc != SQL::OK
      puts "sqlite3_open failed: " + rc.to_s
      exit(1)
    end
    @db = SQL.read_ptr(SQL.db_out)
  end

  def close
    SQL.sqlite3_close(@db)
    @db = nil
  end

  # Run a statement that returns no rows (DDL, INSERT/UPDATE/DELETE).
  def exec(sql)
    rc = SQL.sqlite3_exec(@db, sql, nil, nil, nil)
    if rc != SQL::OK
      puts "exec failed (" + rc.to_s + "): " + SQL.sqlite3_errmsg(@db)
      puts "  sql: " + sql
      exit(1)
    end
  end

  def last_id
    SQL.sqlite3_last_insert_rowid(@db)
  end

  # Prepare and step through a SELECT, returning the resulting stmt
  # pointer. Caller is responsible for finalizing.
  def prepare(sql)
    rc = SQL.sqlite3_prepare_v2(@db, sql, -1, SQL.stmt_out, nil)
    if rc != SQL::OK
      puts "prepare failed (" + rc.to_s + "): " + SQL.sqlite3_errmsg(@db)
      puts "  sql: " + sql
      exit(1)
    end
    SQL.read_ptr(SQL.stmt_out)
  end

  def db
    @db
  end
end

# Convenience wrappers — keep call sites readable.
def step?(stmt)
  SQL.sqlite3_step(stmt) == SQL::ROW
end

def col_text(stmt, i)
  s = SQL.sqlite3_column_text(stmt, i)
  if s == nil
    return ""
  end
  # Copy out — the buffer is invalidated by the next step / finalize.
  s + ""
end

def col_int(stmt, i)
  SQL.sqlite3_column_int(stmt, i)
end

def finalize(stmt)
  SQL.sqlite3_finalize(stmt)
end

# Look up the id of a tag by name (creating it on the fly if missing).
def upsert_tag(blog, name)
  blog.exec("INSERT OR IGNORE INTO tags (name) VALUES ('" + Sql.q(name) + "')")
  stmt = blog.prepare("SELECT id FROM tags WHERE name = '" + Sql.q(name) + "'")
  tid = 0
  if step?(stmt)
    tid = col_int(stmt, 0)
  end
  finalize(stmt)
  tid
end

def add_post(blog, title, body, tag_names)
  blog.exec("INSERT INTO posts (title, body) VALUES ('" +
            Sql.q(title) + "', '" + Sql.q(body) + "')")
  pid = blog.last_id
  tag_names.each { |t|
    tid = upsert_tag(blog, t)
    blog.exec("INSERT INTO post_tags (post_id, tag_id) VALUES (" +
              pid.to_s + ", " + tid.to_s + ")")
  }
  pid
end

def add_comment(blog, post_id, author, body)
  blog.exec("INSERT INTO comments (post_id, author, body) VALUES (" +
            post_id.to_s + ", '" + Sql.q(author) + "', '" + Sql.q(body) + "')")
end

# ---- Demo ----

# Use an in-memory database so each run starts fresh and we don't
# have to worry about cleaning up.
blog = Blog.new(":memory:")

blog.exec(
  "CREATE TABLE posts (" +
    "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
    "title TEXT NOT NULL, " +
    "body TEXT NOT NULL)")
blog.exec(
  "CREATE TABLE tags (" +
    "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
    "name TEXT NOT NULL UNIQUE)")
blog.exec(
  "CREATE TABLE post_tags (" +
    "post_id INTEGER NOT NULL, " +
    "tag_id  INTEGER NOT NULL, " +
    "PRIMARY KEY (post_id, tag_id))")
blog.exec(
  "CREATE TABLE comments (" +
    "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
    "post_id INTEGER NOT NULL, " +
    "author TEXT NOT NULL, " +
    "body TEXT NOT NULL)")

p1 = add_post(blog,
  "Spinel learns to call C",
  "Today the AOT compiler grew an FFI. Now we can drive sqlite3 directly.",
  ["spinel", "ffi", "sqlite"])

p2 = add_post(blog,
  "Tasting o'tea",
  "She said it's the best Earl Grey in London.",
  ["food", "off-topic"])

p3 = add_post(blog,
  "Hashes vs SymIntHash",
  "Symbol-keyed hashes get a dedicated type with no string hashing.",
  ["spinel", "perf"])

add_comment(blog, p1, "alice", "Wonderful — does it work with libcurl too?")
add_comment(blog, p1, "bob",   "I tried sqlite3 myself; the bindings are tidy.")
add_comment(blog, p2, "carol", "Where's the shop?")
add_comment(blog, p3, "dave",  "Nice; the symbol path is hot in our app.")

puts "Posts (with comment + tag counts):"
stmt = blog.prepare(
  "SELECT p.id, p.title, " +
    "(SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS n_comments, " +
    "(SELECT COUNT(*) FROM post_tags WHERE post_id = p.id) AS n_tags " +
    "FROM posts p ORDER BY p.id")
while step?(stmt)
  puts "  [" + col_int(stmt, 0).to_s + "] " + col_text(stmt, 1) +
       "  (" + col_int(stmt, 2).to_s + " comments, " +
       col_int(stmt, 3).to_s + " tags)"
end
finalize(stmt)

puts ""
puts "Posts tagged 'spinel':"
stmt = blog.prepare(
  "SELECT p.title FROM posts p " +
    "JOIN post_tags pt ON pt.post_id = p.id " +
    "JOIN tags t ON t.id = pt.tag_id " +
    "WHERE t.name = 'spinel' ORDER BY p.id")
while step?(stmt)
  puts "  - " + col_text(stmt, 0)
end
finalize(stmt)

puts ""
puts "Comments on the FFI post:"
stmt = blog.prepare(
  "SELECT author, body FROM comments WHERE post_id = " + p1.to_s + " ORDER BY id")
while step?(stmt)
  puts "  " + col_text(stmt, 0) + ": " + col_text(stmt, 1)
end
finalize(stmt)

blog.close
