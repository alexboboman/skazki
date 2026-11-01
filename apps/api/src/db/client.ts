import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";
import { drizzle as drizzleNodePg } from "drizzle-orm/node-postgres";
import { migrate as migrateNodePg } from "drizzle-orm/node-postgres/migrator";
import { drizzle as drizzlePglite } from "drizzle-orm/pglite";
import { migrate as migratePglite } from "drizzle-orm/pglite/migrator";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import pg from "pg";
import * as schema from "./schema.js";

export type Db = PgDatabase<PgQueryResultHKT, typeof schema>;

const migrationsFolder = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../drizzle");

/**
 * Postgres when DATABASE_URL is set (Neon in production), otherwise an embedded
 * PGlite database so the API runs locally with no setup. `dataDir` "memory://"
 * gives a throwaway database for tests.
 */
export async function createDb(options: { databaseUrl?: string; dataDir?: string } = {}): Promise<Db> {
  const databaseUrl = options.databaseUrl ?? process.env.DATABASE_URL;

  if (databaseUrl) {
    const db = drizzleNodePg(new pg.Pool({ connectionString: databaseUrl }), { schema });
    await migrateNodePg(db, { migrationsFolder });
    return db;
  }

  const dataDir = options.dataDir ?? process.env.PGLITE_DIR ?? path.resolve("apps/api/.data/pglite");
  // PGlite creates the database folder but not its parents, so a fresh checkout has no apps/api/.data yet.
  if (!dataDir.includes("://")) {
    await mkdir(path.dirname(dataDir), { recursive: true });
  }

  const db = drizzlePglite(new PGlite(dataDir), { schema });
  await migratePglite(db, { migrationsFolder });
  return db;
}
