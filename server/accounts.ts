// Accounts: sign in once, play several characters. An account is a name and a password (kept as a
// salted scrypt hash, never in the clear); the first sign-in with a new name opens the account.
// Each character (a Builder or a pilot, by name) belongs to the first account that signs in to
// play it, and from then on to that account only. Without a server that requires sign-in, guests
// may still play characters no account has claimed.
//
// Side locks: one side per front per account. A front is a contested planet's campaign; once any
// of an account's characters fights (or donates) there for a faction, none of its characters may
// do it for another faction until that campaign ends and the planet locks.
//
// Saved in the galaxy as g.accounts (key -> account) and g.owners ('role/name' -> key); neither ever
// goes to an app. Session tokens are in memory only: after a restart, apps sign in with the
// password again.

const crypto: typeof import('node:crypto') = require('node:crypto');
const T = require('./tunables.ts');

interface Lock {
  faction: string;
  until: number;
  by: string; // the character that took the side, 'role/name'
}
interface Account {
  name: string;
  salt: string;
  hash: string;
  createdAt: number;
  characters: string[]; // 'role/name'
  locks: Record<string, Lock>; // planet id -> the side taken there
}
interface Galaxy {
  accounts?: Record<string, Account>;
  owners?: Record<string, string>;
  [key: string]: unknown;
}
type Result = { ok: true; [key: string]: unknown } | { ok: false; reason: string };

const KEY_LEN = 32;
const SCRYPT = { N: 16384, r: 8, p: 1 };
const TOKEN_MS = 30 * 24 * 3600_000; // a session token lasts this long (or until the server restarts)
const MINUTE = 60_000;

const fail = (reason: string): Result => ({ ok: false, reason });

function ensure(g: Galaxy): { accounts: Record<string, Account>; owners: Record<string, string> } {
  g.accounts ||= {};
  g.owners ||= {};
  return { accounts: g.accounts, owners: g.owners };
}

// The key an account is filed under: its name, the same however it's capitalized.
function keyOf(name: string): string {
  return String(name).trim().toLowerCase();
}

function charKey(role: string, name: string): string {
  return `${role}/${name}`;
}

function hashOf(password: string, salt: string): string {
  return crypto.scryptSync(password, Buffer.from(salt, 'hex'), KEY_LEN, SCRYPT).toString('hex');
}

// Sign-in attempts in the last minute, per account (wrong passwords from anywhere count).
const attempts = new Map<string, number[]>();
// Session tokens: token -> { key, until }.
const tokens = new Map<string, { key: string; until: number }>();

function throttled(key: string, now: number): boolean {
  const recent = (attempts.get(key) || []).filter((t) => now - t < MINUTE);
  attempts.set(key, recent);
  return recent.length >= T.get().accounts.attemptsPerMinute;
}

function failedAttempt(key: string, now: number): void {
  attempts.set(key, [...(attempts.get(key) || []), now]);
}

function issueToken(key: string, now: number): string {
  const token = crypto.randomBytes(24).toString('base64url');
  tokens.set(token, { key, until: now + TOKEN_MS });
  return token;
}

// Signs in to account `name` with `password`, or a token from an earlier sign-in; a new name opens
// a new account. Returns the account's key, a fresh token, and whether it was just opened.
function signIn(g: Galaxy, { name, password, token }: { name?: unknown; password?: unknown; token?: unknown }, now = Date.now()): Result {
  const { accounts } = ensure(g);
  const cfg = T.get().accounts;
  const display = String(name ?? '').trim();
  const key = keyOf(display);
  if (!key) return fail('type an account name to sign in');
  if (display.length > cfg.nameMax) return fail(`account names are at most ${cfg.nameMax} characters`);
  if (key in Object.prototype) return fail(`"${display}" can't be an account name: pick another`);
  if (typeof token === 'string' && token) {
    const t = tokens.get(token);
    if (t && t.key === key && t.until > now && Object.hasOwn(accounts, key)) return { ok: true, key, token, created: false };
  }
  if (typeof password !== 'string' || !password) return fail(`type the password for ${display}`);
  if (throttled(key, now)) return fail('too many sign-in attempts: wait a minute and try again');
  if (!Object.hasOwn(accounts, key)) {
    if (password.length < cfg.passwordMin) return fail(`a new account's password needs at least ${cfg.passwordMin} characters`);
    const salt = crypto.randomBytes(16).toString('hex');
    accounts[key] = { name: display, salt, hash: hashOf(password, salt), createdAt: now, characters: [], locks: {} };
    return { ok: true, key, token: issueToken(key, now), created: true };
  }
  const a = accounts[key];
  const got = Buffer.from(hashOf(password, a.salt), 'hex');
  const want = Buffer.from(a.hash, 'hex');
  if (got.length !== want.length || !crypto.timingSafeEqual(got, want)) {
    failedAttempt(key, now);
    return fail(`wrong password for the account ${a.name}`);
  }
  return { ok: true, key, token: issueToken(key, now), created: false };
}

// Who owns a character: an account's key, or null.
function ownerOf(g: Galaxy, role: string, name: string): string | null {
  const { owners } = ensure(g);
  const k = charKey(role, name);
  return Object.hasOwn(owners, k) ? owners[k] : null;
}

// May the account `key` (null: a guest) play this character? An account claims a character nobody
// owns, up to accounts.charactersMax of them.
function claim(g: Galaxy, key: string | null, role: string, name: string): Result {
  const { accounts, owners } = ensure(g);
  const owner = ownerOf(g, role, name);
  const what = role === 'builder' ? 'Builder' : 'pilot';
  if (!key) return owner ? fail(`the ${what} ${name} belongs to an account: sign in to play it`) : { ok: true, claimed: false };
  if (owner && owner !== key) return fail(`the ${what} ${name} belongs to another account: pick another name`);
  if (owner) return { ok: true, claimed: false };
  const a = accounts[key];
  if (!a) return fail('no such account');
  const max = T.get().accounts.charactersMax;
  if (a.characters.length >= max) return fail(`an account can have ${max} characters at most`);
  owners[charKey(role, name)] = key;
  a.characters.push(charKey(role, name));
  return { ok: true, claimed: true };
}

// "3d 4h", "2h 05m" or "12m": how long until `ms` from now.
function timeLeft(ms: number): string {
  const m = Math.max(1, Math.ceil(ms / MINUTE));
  if (m >= 1440) return `${Math.floor(m / 1440)}d ${Math.floor((m % 1440) / 60)}h`;
  if (m >= 60) return `${Math.floor(m / 60)}h ${String(m % 60).padStart(2, '0')}m`;
  return `${m}m`;
}

// The side account `key` has taken on a front, while it holds.
function lockOn(g: Galaxy, key: string | null, planet: string, now = Date.now()): Lock | null {
  if (!key || !T.get().sideLock.on) return null;
  const a = ensure(g).accounts[key];
  const lock = a && Object.hasOwn(a.locks, planet) ? a.locks[planet] : null;
  return lock && lock.until > now ? lock : null;
}

// May account `key` act for `faction` on front `planet`? (Guests: always; a guest character has
// one faction for good.) `planetName` and `factionName` word the refusal.
function checkSide(g: Galaxy, key: string | null, planet: string, faction: string, now = Date.now(), { planetName = planet, factionName = (f: string) => f } = {}): Result {
  const lock = lockOn(g, key, planet, now);
  if (!lock || lock.faction === faction) return { ok: true };
  const who = lock.by.slice(lock.by.indexOf('/') + 1);
  return fail(`your account took the ${factionName(lock.faction)}'s side on ${planetName} this campaign (${who}): it can fight for nobody else there until the campaign ends, in ${timeLeft(lock.until - now)}`);
}

// Account `key` takes `faction`'s side on front `planet` until `until` (the campaign's end), as
// character `by`. A side already taken stays (checkSide comes first).
function takeSide(g: Galaxy, key: string | null, planet: string, faction: string, until: number, by: string, now = Date.now()): Lock | null {
  if (!key || !T.get().sideLock.on || !(until > now)) return null;
  const a = ensure(g).accounts[key];
  if (!a) return null;
  const held = lockOn(g, key, planet, now);
  if (held) return held;
  for (const [p, l] of Object.entries(a.locks)) if (l.until <= now) delete a.locks[p]; // tidy the ended ones
  return (a.locks[planet] = { faction, until, by });
}

// What an account's owner may see of it.
function view(g: Galaxy, key: string, now = Date.now()) {
  const a = ensure(g).accounts[key];
  if (!a) return null;
  const locks: Record<string, Lock> = {};
  for (const [p, l] of Object.entries(a.locks)) if (l.until > now) locks[p] = l;
  return { name: a.name, characters: a.characters.slice(), locks };
}

// For tests: forget the sign-in attempts and tokens.
function reset(): void {
  attempts.clear();
  tokens.clear();
}

module.exports = { TOKEN_MS, keyOf, charKey, signIn, ownerOf, claim, lockOn, checkSide, takeSide, timeLeft, view, reset };
