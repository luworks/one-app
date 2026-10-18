CREATE TABLE event (
  id           INTEGER PRIMARY KEY,
  uid          TEXT NOT NULL UNIQUE,
  device       TEXT NOT NULL,
  ts           INTEGER NOT NULL,
  tz           INTEGER NOT NULL,
  day          INTEGER NOT NULL,
  tier         INTEGER NOT NULL,
  kind         TEXT NOT NULL,
  actor        TEXT NOT NULL,
  channel      TEXT,
  session      TEXT,
  thread       TEXT,
  subject_kind TEXT,
  subject_ref  TEXT,
  approval     TEXT,
  undo_of      TEXT,
  title        TEXT,
  before_txt   TEXT,
  after_txt    TEXT,
  before_ts    INTEGER,
  after_ts     INTEGER,
  props        TEXT NOT NULL DEFAULT '{}',
  v            INTEGER NOT NULL DEFAULT 1,
  sync         INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX event_ts       ON event(ts DESC, id DESC);
CREATE INDEX event_tier_ts  ON event(tier, ts DESC, id DESC);
CREATE INDEX event_actor_ts ON event(actor, ts DESC, id DESC);
CREATE INDEX event_subject  ON event(subject_ref, ts DESC) WHERE subject_ref IS NOT NULL;
CREATE INDEX event_kind_day ON event(kind, day);
CREATE INDEX event_undo     ON event(undo_of) WHERE undo_of IS NOT NULL;
CREATE TABLE snapshot (
  event_uid TEXT PRIMARY KEY REFERENCES event(uid) ON DELETE CASCADE,
  data      BLOB NOT NULL
);
CREATE TABLE content (
  event_uid  TEXT NOT NULL REFERENCES event(uid) ON DELETE CASCADE,
  field      TEXT NOT NULL,
  before_txt TEXT,
  after_txt  TEXT,
  PRIMARY KEY (event_uid, field)
) WITHOUT ROWID;
CREATE TABLE rollup_daily (
  day    INTEGER NOT NULL,
  kind   TEXT NOT NULL,
  actor  TEXT NOT NULL,
  n      INTEGER NOT NULL,
  sum_ms INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, kind, actor)
) WITHOUT ROWID;
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
