import { Database } from "bun:sqlite";
import { emptyState, type State } from "./engine";
export interface Store {
  load(): State;
  save(state: State): void | Promise<void>;
}
export class SQLiteStore implements Store {
  db: Database;
  constructor(path = "bp26.sqlite") {
    this.db = new Database(path);
    this.db.run("PRAGMA journal_mode=WAL");
    this.db.run(
      "CREATE TABLE IF NOT EXISTS game_state (id INTEGER PRIMARY KEY, value TEXT NOT NULL)",
    );
  }
  load(): State {
    const row = this.db
      .query("SELECT value FROM game_state WHERE id=1")
      .get() as { value: string } | null;
    return row ? JSON.parse(row.value) : emptyState();
  }
  save(state: State) {
    this.db.transaction(() =>
      this.db.run(
        "INSERT INTO game_state VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET value=excluded.value",
        [JSON.stringify(state)],
      ),
    )();
  }
  close() {
    this.db.close();
  }
}
