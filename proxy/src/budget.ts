import { DurableObject } from "cloudflare:workers";

/** Output and input tokens for one call, or the change in what one cost once it's answered. */
export interface Tokens {
  output: number;
  input: number;
}

export interface Caps {
  deviceOutput: number;
  globalOutput: number;
  deviceInput: number;
  globalInput: number;
}

/** Tokens spent per phone per UTC day. One instance holds every phone, so a phone's totals and everyone's are checked
 *  and changed together, and two requests at the same moment can't both slip under a cap. */
export class Budget extends DurableObject<object> {
  private sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: object) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`CREATE TABLE IF NOT EXISTS spent (
      day TEXT NOT NULL, device TEXT NOT NULL, output INTEGER NOT NULL, input INTEGER NOT NULL,
      PRIMARY KEY (day, device))`);
  }

  /** Sets aside the most one call could cost, before it's made. Returns the day it was counted on, or null when it would
   *  pass the phone's or everyone's allowance for today, and then nothing is set aside. */
  reserve(device: string, cost: Tokens, caps: Caps): string | null {
    const day = today();
    // Earlier days' counts are no longer needed.
    this.sql.exec("DELETE FROM spent WHERE day < ?", day);
    const mine = this.sql.exec<{ o: number; i: number }>(
      "SELECT COALESCE(SUM(output), 0) AS o, COALESCE(SUM(input), 0) AS i FROM spent WHERE day = ? AND device = ?", day, device).one();
    const all = this.sql.exec<{ o: number; i: number }>(
      "SELECT COALESCE(SUM(output), 0) AS o, COALESCE(SUM(input), 0) AS i FROM spent WHERE day = ?", day).one();
    if (mine.o + cost.output > caps.deviceOutput || all.o + cost.output > caps.globalOutput
      || mine.i + cost.input > caps.deviceInput || all.i + cost.input > caps.globalInput) return null;
    this.sql.exec(
      `INSERT INTO spent (day, device, output, input) VALUES (?, ?, ?, ?)
       ON CONFLICT (day, device) DO UPDATE SET output = output + excluded.output, input = input + excluded.input`,
      day, device, cost.output, cost.input);
    return day;
  }

  /** Turns what was set aside into what the call really cost. `change` is the real count minus what was set aside, so
   *  usually negative. After midnight that day's row is gone and there's nothing to change. */
  settle(device: string, day: string, change: Tokens): void {
    if (change.output === 0 && change.input === 0) return;
    this.sql.exec(
      "UPDATE spent SET output = MAX(0, output + ?), input = MAX(0, input + ?) WHERE day = ? AND device = ?",
      change.output, change.input, day, device);
  }
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}
