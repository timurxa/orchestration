#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif

#include <sqlite3.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <locale.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <wchar.h>
#include <termios.h>

/* Enable termbox2's 24-bit output attributes. */
#define TB_OPT_ATTR_W 32
#define TB_IMPL
#include "vendor/termbox2/termbox2.h"

#define PAGE_SIZE 256
#define MAX_DEPTH 16
#define MAX_KEY 1024
#define MAX_LABEL 1024
#define DAG_LAYER_STEP 6
#define DAG_SLOT_STEP 4

/* Ghostty's configured high_contrast_light theme.  Use truecolor rather than
   ANSI palette slots: its slot 7 is light gray on the white terminal surface. */
#define UI_BG             0xffffffu
#define UI_FG             0x171717u
#define UI_BORDER         0x3c3c3cu
#define UI_ACCENT         0x53001au
#define UI_TEAL           0x002738u
#define UI_GREEN          0x082c00u
#define UI_GOLD           0x2f2100u
#define UI_FAILED         0x9b1c31u
#define UI_STALE          0x14627au
#define UI_IDLE           0x52616bu
#define UI_ERROR_BG       0xfbe9efu
#define UI_SELECTED_FG    0xf4e9d2u
#define UI_SELECTED_BG    0x171717u

static const char *const table_names[] = {
  "run_metadata", "run_execution", "checkpoint", "work_occurrence",
  "work_edge", "artifact", "predecessor", "model_attempt",
  "worker_session", "conversation_event", "artifact_file"
};
static const int current_table_count = 10;
static volatile sig_atomic_t stop_requested = 0;

typedef struct {
  char table[40];
  char key_column[40];
  char key[MAX_KEY];
  char label[MAX_LABEL];
  char state[40];
  bool rowid_key;
} Item;

typedef enum {
  view_graph,
  view_node,
  view_artifact,
  view_attempt,
  view_session,
  view_tables,
  view_table_rows,
  view_events,
  view_failures,
  view_event_detail
} ViewKind;

typedef struct {
  ViewKind kind;
  Item parent;
  int table_index;
  int offset;
  int selected;
  int detail_scroll;
  bool reveal_selection;
  bool transcript_initialized;
  bool graph_neighbor_outgoing;
  bool graph_neighbor_ready;
  bool graph_reveal_selection;
  int64_t graph_neighbor_origin;
  size_t graph_neighbor_index;
  int64_t graph_pan_x;
  int64_t graph_pan_y;
  char anchor_table[40];
  char anchor_key[MAX_KEY];
  char anchor_label[MAX_LABEL];
} View;

typedef struct {
  char kind[32];
  char key[256];
  char label[96];
  char *text;
  size_t text_len;
  size_t text_cap;
  int64_t primary_event;
  int64_t timestamp;
  int64_t *events;
  size_t event_count;
  size_t event_cap;
  char rpc_id[128];
  char call_id[256];
  char turn_id[256];
  bool rpc_request;
  bool rpc_result;
  bool paired_result;
  bool lifecycle_tool;
  bool hidden;
  bool exact_session;
  bool completed;
} TranscriptCard;

typedef struct {
  int64_t id;
  char glyph;
  char state[16];
  size_t rank;
  size_t point;
  bool selected;
  bool neighbor;
} DagNode;

typedef struct {
  size_t source;
  size_t target;
  size_t path_start;
  size_t path_count;
} DagEdge;

typedef struct {
  size_t node;
  size_t layer;
  size_t order;
  size_t stable;
  double score;
  size_t samples;
  int64_t x;
  int64_t y;
  bool is_node;
} DagPoint;

typedef struct {
  size_t source;
  size_t target;
  size_t edge;
} DagSegment;

typedef struct {
  size_t start;
  size_t count;
} DagLayer;

typedef struct {
  DagNode *nodes;
  size_t node_count;
  size_t node_capacity;
  DagEdge *edges;
  size_t edge_count;
  size_t edge_capacity;
  DagPoint *points;
  size_t point_count;
  DagSegment *segments;
  size_t segment_count;
  size_t *paths;
  size_t path_count;
  size_t *layer_order;
  DagLayer *layers;
  size_t layer_count;
  int64_t world_width;
  int64_t world_height;
} DagLayout;

typedef struct {
  unsigned char glyph;
  unsigned char directions;
  size_t owner;
  bool occupied;
  bool shared;
  bool branch;
  bool highlighted;
} DagCell;

typedef struct {
  sqlite3 *db;
  View views[MAX_DEPTH];
  int depth;
  Item page[PAGE_SIZE];
  int page_count;
  char database_path[2048];
  int schema_version;
  char status[512];
  char header[1024];
  bool help;
  bool details_focused;
  int64_t now_ns;
  int page_depth;
  ViewKind page_kind;
  bool page_valid;
  TranscriptCard *chat;
  int chat_count;
  char chat_assoc[4];
} Ui;

static void on_signal(int signal_number) {
  (void)signal_number;
  stop_requested = 1;
}

static int64_t wall_time_ns(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_REALTIME, &now) != 0)
    return (int64_t)time(NULL) * 1000000000LL;
  return (int64_t)now.tv_sec * 1000000000LL + now.tv_nsec;
}

static const char *sqlite_error(sqlite3 *db) {
  return db ? sqlite3_errmsg(db) : "SQLite unavailable";
}

static bool table_exists(sqlite3 *db, const char *name) {
  sqlite3_stmt *stmt = NULL;
  bool found = false;
  if (sqlite3_prepare_v2(db,
      "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?1", -1,
      &stmt, NULL) == SQLITE_OK) {
    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_STATIC);
    found = sqlite3_step(stmt) == SQLITE_ROW;
  }
  sqlite3_finalize(stmt);
  return found;
}

static bool column_exists(sqlite3 *db, const char *table, const char *column) {
  sqlite3_stmt *stmt = NULL;
  bool found = false;
  if (sqlite3_prepare_v2(db, "SELECT 1 FROM pragma_table_info(?1) WHERE name=?2",
      -1, &stmt, NULL) == SQLITE_OK) {
    sqlite3_bind_text(stmt, 1, table, -1, SQLITE_STATIC);
    sqlite3_bind_text(stmt, 2, column, -1, SQLITE_STATIC);
    found = sqlite3_step(stmt) == SQLITE_ROW;
  }
  sqlite3_finalize(stmt);
  return found;
}

static bool check_wal_sidecars(const char *path, char *error, size_t error_size) {
  char wal[4096];
  char shm[4096];
  struct stat info;
  int n1 = snprintf(wal, sizeof(wal), "%s-wal", path);
  int n2 = snprintf(shm, sizeof(shm), "%s-shm", path);
  if (n1 < 0 || n2 < 0 || (size_t)n1 >= sizeof(wal) ||
      (size_t)n2 >= sizeof(shm)) {
    snprintf(error, error_size, "database path is too long");
    return false;
  }
  if (stat(wal, &info) != 0) return true;
  if (access(wal, R_OK) != 0 || access(shm, R_OK) != 0) {
    snprintf(error, error_size,
        "active WAL reads need readable existing -wal and -shm sidecars");
    return false;
  }
  return true;
}

static bool open_store(Ui *ui, char *error, size_t error_size) {
  sqlite3_stmt *stmt = NULL;
  int version = 0;
  int rc;
  if (sqlite3_libversion_number() < 3022000) {
    snprintf(error, error_size, "SQLite 3.22 or newer is required for read-only WAL access");
    return false;
  }
  if (!check_wal_sidecars(ui->database_path, error, error_size)) return false;
  rc = sqlite3_open_v2(ui->database_path, &ui->db,
      SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
  if (rc != SQLITE_OK) {
    snprintf(error, error_size, "cannot open read-only: %s", sqlite_error(ui->db));
    return false;
  }
  sqlite3_busy_timeout(ui->db, 100);
  if (sqlite3_db_readonly(ui->db, "main") != 1) {
    snprintf(error, error_size, "SQLite did not open the database read-only");
    return false;
  }
  rc = sqlite3_prepare_v2(ui->db, "PRAGMA user_version", -1, &stmt, NULL);
  if (rc == SQLITE_OK && sqlite3_step(stmt) == SQLITE_ROW)
    version = sqlite3_column_int(stmt, 0);
  sqlite3_finalize(stmt);
  if (version != 7 && version != 8) {
    snprintf(error, error_size, "unsupported SQLite schema version %d (need 7 or 8)", version);
    return false;
  }
  ui->schema_version = version;
  for (int i = 0; i < current_table_count; ++i) {
    if (version == 7 &&
        (strcmp(table_names[i], "work_occurrence") == 0 ||
         strcmp(table_names[i], "work_edge") == 0)) continue;
    if (!table_exists(ui->db, table_names[i])) {
      snprintf(error, error_size, "schema %d database is missing table %s",
          version, table_names[i]);
      return false;
    }
  }
  static const struct { const char *table, *column; } dag_columns[] = {
    {"work_occurrence", "work_id"}, {"work_occurrence", "flow_key"},
    {"work_occurrence", "kind"}, {"work_occurrence", "state"},
    {"work_occurrence", "input_artifact_id"}, {"work_occurrence", "output_artifact_id"},
    {"work_occurrence", "request_id"}, {"work_occurrence", "expansion_id"},
    {"work_occurrence", "join_id"}, {"work_occurrence", "root_name"},
    {"work_occurrence", "slot"}, {"work_edge", "source_work_id"},
    {"work_edge", "target_work_id"}, {"work_edge", "relation"},
    {"work_edge", "position"}
  };
  if (version == 8) for (size_t i = 0; i < sizeof(dag_columns) / sizeof(dag_columns[0]); ++i) {
    if (!column_exists(ui->db, dag_columns[i].table, dag_columns[i].column)) {
      snprintf(error, error_size, "schema 8 database is missing column %s.%s",
          dag_columns[i].table, dag_columns[i].column);
      return false;
    }
  }
  static const struct { const char *table, *column; } required_columns[] = {
    {"run_metadata", "singleton"}, {"run_metadata", "run_id"},
    {"run_metadata", "workflow_id"}, {"run_metadata", "workflow_fingerprint"},
    {"run_metadata", "workflow_manifest_json"}, {"run_metadata", "codec_version"},
    {"run_metadata", "checkpoint_version"}, {"run_metadata", "status"},
    {"run_metadata", "active_execution_id"}, {"run_metadata", "history_started_at_ns"},
    {"run_execution", "execution_id"}, {"run_execution", "owner_token"},
    {"run_execution", "owner_pid"}, {"run_execution", "started_at_ns"},
    {"run_execution", "heartbeat_at_ns"}, {"run_execution", "ended_at_ns"},
    {"checkpoint", "singleton"}, {"checkpoint", "sequence"},
    {"checkpoint", "format_version"}, {"checkpoint", "status"},
    {"checkpoint", "payload_text"},
    {"artifact", "artifact_id"}, {"artifact", "codec_id"},
    {"artifact", "codec_version"}, {"artifact", "payload_text"},
    {"artifact", "operation"}, {"artifact", "flow_kind"}, {"artifact", "request_id"},
    {"predecessor", "artifact_id"},
    {"predecessor", "predecessor_id"}, {"predecessor", "position"},
    {"model_attempt", "request_id"}, {"model_attempt", "state"},
    {"model_attempt", "payload_text"},
    {"model_attempt", "flow_key"}, {"model_attempt", "input_artifact_id"},
    {"model_attempt", "reserved_output_artifact_id"}, {"model_attempt", "output_artifact_id"},
    {"model_attempt", "model"}, {"model_attempt", "effort"},
    {"worker_session", "session_id"}, {"worker_session", "request_id"},
    {"worker_session", "execution_id"}, {"worker_session", "generation"},
    {"worker_session", "agent_id"}, {"worker_session", "thread_id"},
    {"worker_session", "state"},
    {"conversation_event", "event_id"}, {"conversation_event", "execution_id"},
    {"conversation_event", "session_id"}, {"conversation_event", "request_id"},
    {"conversation_event", "agent_id"}, {"conversation_event", "rpc_id"},
    {"conversation_event", "thread_id"}, {"conversation_event", "turn_id"},
    {"conversation_event", "direction"}, {"conversation_event", "kind"},
    {"conversation_event", "raw_json"}, {"conversation_event", "details_json"},
    {"conversation_event", "write_state"}, {"conversation_event", "timestamp_ns"}
  };
  for (size_t i = 0; i < sizeof(required_columns) / sizeof(required_columns[0]); ++i) {
    if (!column_exists(ui->db, required_columns[i].table, required_columns[i].column)) {
      snprintf(error, error_size, "schema %d database is missing column %s.%s",
          version,
          required_columns[i].table, required_columns[i].column);
      return false;
    }
  }
  return true;
}

static void item_set(Item *item, const char *table, const char *key_column,
    const char *key, const char *label) {
  memset(item, 0, sizeof(*item));
  snprintf(item->table, sizeof(item->table), "%s", table ? table : "");
  snprintf(item->key_column, sizeof(item->key_column), "%s",
      key_column ? key_column : "");
  snprintf(item->key, sizeof(item->key), "%s", key ? key : "");
  snprintf(item->label, sizeof(item->label), "%s", label ? label : "");
}

static void item_from_query(Item *item, sqlite3_stmt *stmt) {
  const unsigned char *table = sqlite3_column_text(stmt, 0);
  const unsigned char *key_column = sqlite3_column_text(stmt, 1);
  const unsigned char *key = sqlite3_column_text(stmt, 2);
  const unsigned char *label = sqlite3_column_text(stmt, 3);
  item_set(item, (const char *)table, (const char *)key_column,
      (const char *)key, (const char *)label);
  if (sqlite3_column_count(stmt) > 4) {
    const unsigned char *state = sqlite3_column_text(stmt, 4);
    snprintf(item->state, sizeof(item->state), "%s", state ? (const char *)state : "");
  }
}

static int load_query(Ui *ui, const char *sql, const char *key,
    int has_key, int offset, Item *items) {
  sqlite3_stmt *stmt = NULL;
  int rc = sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL);
  int count = 0;
  if (rc != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "read failed: %.440s", sqlite_error(ui->db));
    return -1;
  }
  if (has_key) sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT);
  sqlite3_bind_int(stmt, has_key ? 2 : 1, PAGE_SIZE);
  sqlite3_bind_int(stmt, has_key ? 3 : 2, offset);
  while ((rc = sqlite3_step(stmt)) == SQLITE_ROW && count < PAGE_SIZE) {
    item_from_query(&items[count++], stmt);
  }
  if (rc != SQLITE_DONE) {
    snprintf(ui->status, sizeof(ui->status), "read failed: %.440s", sqlite_error(ui->db));
    count = -1;
  }
  sqlite3_finalize(stmt);
  return count;
}

static void draw_codepoint(int x, int y, uint32_t codepoint, uintattr_t fg,
    uintattr_t bg, int right_edge) {
  wchar_t wc = (wchar_t)codepoint;
  int width = wcwidth(wc);
  if (width < 1) width = 1;
  if (x >= 0 && x + width <= right_edge && y >= 0 && y < tb_height())
    tb_set_cell(x, y, codepoint, fg, bg);
}

static int decode_utf8(const char *text, size_t length, size_t *used,
    uint32_t *codepoint) {
  mbstate_t state;
  wchar_t wc = 0;
  memset(&state, 0, sizeof(state));
  size_t n = mbrtowc(&wc, text, length, &state);
  if (n == (size_t)-1 || n == (size_t)-2 || n == 0) {
    *used = 1;
    *codepoint = 0xfffd;
    return 1;
  }
  *used = n;
  *codepoint = (uint32_t)wc;
  return 0;
}

static void draw_wrapped(int x, int y, int width, int height, int scroll,
    const char *text, uintattr_t fg, uintattr_t bg) {
  size_t length = strlen(text);
  size_t offset = 0;
  int line = 0;
  int column = 0;
  const int right = x + width;
  while (offset < length) {
    size_t used = 1;
    uint32_t cp = 0xfffd;
    decode_utf8(text + offset, length - offset, &used, &cp);
    offset += used;
    if (cp == '\n') {
      line++;
      column = 0;
      continue;
    }
    if (cp == '\r') {
      const char *visible = "\\r";
      for (int i = 0; i < 2; ++i) {
        if (column >= width) { line++; column = 0; }
        if (line >= scroll && line - scroll < height)
          draw_codepoint(x + column, y + line - scroll, (uint32_t)visible[i], fg, bg, right);
        column++;
      }
      continue;
    }
    if (cp == '\t') cp = ' ';
    if (cp < 0x20 || cp == 0x7f) cp = '?';
    int cw = wcwidth((wchar_t)cp);
    if (cw < 1) { cp = 0xfffd; cw = 1; }
    if (column + cw > width) { line++; column = 0; }
    if (line >= scroll && line - scroll < height)
      draw_codepoint(x + column, y + line - scroll, cp, fg, bg, right);
    column += cw;
  }
}

static void draw_plain(int x, int y, int width, const char *text,
    uintattr_t fg, uintattr_t bg) {
  draw_wrapped(x, y, width, 1, 0, text, fg, bg);
}

static void fill_row(int x, int y, int width, uintattr_t fg, uintattr_t bg) {
  for (int col = 0; col < width; ++col)
    tb_set_cell(x + col, y, ' ', fg, bg);
}

static const char *context_title(const View *view) {
  switch (view->kind) {
    case view_graph: return "RUNTIME WORK DAG";
    case view_node: return "WORK RELATIONSHIPS";
    case view_artifact: return "ARTIFACT LINEAGE";
    case view_attempt: return "REQUEST RELATIONSHIPS";
    case view_session: return "LLM CONVERSATION";
    case view_tables: return "APPLICATION TABLES";
    case view_table_rows: return "TABLE ROWS";
    case view_events: return "RUN EVENT STREAM";
    case view_failures: return "RECORDED FAILURES";
    case view_event_detail: return "EVENT";
  }
  return "RECORDS";
}

static Item selected_item(Ui *ui, View *view) {
  if (view->selected < 0 || view->selected >= ui->page_count) return view->parent;
  return ui->page[view->selected];
}

static int table_index(const char *name) {
  int count = current_table_count + (strcmp(name, "artifact_file") == 0 ? 1 : 0);
  for (int i = 0; i < count; ++i) {
    int index = i < current_table_count ? i : current_table_count;
    if (strcmp(table_names[index], name) == 0) return index;
  }
  return -1;
}

static int load_table_rows(Ui *ui, View *view, Item *items) {
  const char *table = table_names[view->table_index];
  char sql[512];
  snprintf(sql, sizeof(sql),
      "SELECT '%s','rowid',CAST(rowid AS TEXT),'rowid '||rowid "
      "FROM \"%s\" ORDER BY rowid LIMIT ?1 OFFSET ?2", table, table);
  int count = load_query(ui, sql, NULL, 0, view->offset, items);
  if (count > 0)
    for (int i = 0; i < count; ++i) items[i].rowid_key = true;
  return count;
}

static char work_glyph(const char *kind) {
  if (strcmp(kind, "model") == 0) return 'M';
  if (strcmp(kind, "reference") == 0) return 'R';
  if (strcmp(kind, "raw") == 0) return 'A';
  if (strcmp(kind, "iterator") == 0) return 'I';
  if (strcmp(kind, "so") == 0) return 'S';
  if (strcmp(kind, "fanout") == 0) return 'F';
  if (strcmp(kind, "lift") == 0) return 'L';
  if (strcmp(kind, "join") == 0) return 'J';
  return 'W';
}

static char work_state_mark(const char *state) {
  if (strcmp(state, "active") == 0) return '*';
  if (strcmp(state, "running") == 0) return '>';
  if (strcmp(state, "waiting") == 0) return '~';
  if (strcmp(state, "queued") == 0) return '.';
  if (strcmp(state, "completed") == 0) return '+';
  if (strcmp(state, "failed") == 0) return '!';
  return '?';
}

static int load_work_nodes(Ui *ui, int offset, Item *items) {
  static const char sql[] =
    "SELECT w.work_id,w.flow_key,w.kind,CASE WHEN w.kind='model' AND EXISTS("
    "SELECT 1 FROM model_attempt a JOIN worker_session s USING(request_id) "
    "JOIN run_execution x ON x.execution_id=s.execution_id JOIN run_metadata r ON r.singleton=1 "
    "WHERE a.request_id=w.request_id AND s.execution_id=r.active_execution_id "
    "AND x.execution_id=r.active_execution_id AND r.status='running' AND x.ended_at_ns=0 "
    "AND s.state IN ('starting','working') AND a.state NOT IN ('sasCommitted','sasFailed') "
    "AND x.heartbeat_at_ns BETWEEN ?3-6000000000 AND ?3) THEN 'active' ELSE w.state END, w.root_name,"
    "(SELECT COUNT(*) FROM work_edge e WHERE e.target_work_id=w.work_id),"
    "(SELECT COUNT(*) FROM work_edge e WHERE e.source_work_id=w.work_id) "
    "FROM work_occurrence w ORDER BY w.work_id LIMIT ?1 OFFSET ?2";
  sqlite3_stmt *stmt = NULL;
  if (!table_exists(ui->db, "work_occurrence")) return 0;
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "DAG read failed: %.430s", sqlite_error(ui->db));
    return -1;
  }
  sqlite3_bind_int(stmt, 1, PAGE_SIZE);
  sqlite3_bind_int(stmt, 2, offset);
  sqlite3_bind_int64(stmt, 3, ui->now_ns);
  int count = 0, rc;
  while ((rc = sqlite3_step(stmt)) == SQLITE_ROW && count < PAGE_SIZE) {
    int64_t id = sqlite3_column_int64(stmt, 0);
    const char *key = (const char *)sqlite3_column_text(stmt, 1);
    const char *kind = (const char *)sqlite3_column_text(stmt, 2);
    const char *state = (const char *)sqlite3_column_text(stmt, 3);
    const char *root = (const char *)sqlite3_column_text(stmt, 4);
    char label[MAX_LABEL];
    char glyph = work_glyph(kind ? kind : "");
    char mark = work_state_mark(state ? state : "");
    const char *name = root && root[0] ? root : (key ? key : "?");
    const char *short_name = strrchr(name, '/');
    if (short_name && short_name[1]) name = short_name + 1;
    snprintf(label, sizeof(label), "#%-5" PRId64 " %c%c %-5s in:%-2d out:%-2d %.700s",
        id, glyph, mark, state ? state : "?", sqlite3_column_int(stmt, 5),
        sqlite3_column_int(stmt, 6), name);
    item_set(&items[count], "work_occurrence", "work_id", "", label);
    snprintf(items[count].key, sizeof(items[count].key), "%" PRId64, id);
    snprintf(items[count].state, sizeof(items[count].state), "%s", state ? state : "");
    count++;
  }
  if (rc != SQLITE_DONE) {
    snprintf(ui->status, sizeof(ui->status), "DAG read failed: %.430s", sqlite_error(ui->db));
    count = -1;
  }
  sqlite3_finalize(stmt);
  return count;
}

static bool live_model_request(Ui *ui, const char *request_id) {
  static const char sql[] =
    "SELECT EXISTS(SELECT 1 FROM model_attempt a JOIN worker_session s USING(request_id) "
    "JOIN run_execution x ON x.execution_id=s.execution_id JOIN run_metadata r ON r.singleton=1 "
    "WHERE a.request_id=?1 AND s.execution_id=r.active_execution_id "
    "AND x.execution_id=r.active_execution_id AND r.status='running' AND x.ended_at_ns=0 "
    "AND s.state IN ('starting','working') AND a.state NOT IN ('sasCommitted','sasFailed') "
    "AND x.heartbeat_at_ns BETWEEN ?2-6000000000 AND ?2)";
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
  sqlite3_bind_text(stmt, 1, request_id, -1, SQLITE_TRANSIENT);
  sqlite3_bind_int64(stmt, 2, ui->now_ns);
  bool active = sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) != 0;
  sqlite3_finalize(stmt);
  return active;
}

static int load_items_fixed(Ui *ui, View *view, Item *items) {
  /* Each query returns table, key column, key, label. Table names are fixed
     in this file; user input is bound only as values. */
  static const char node_sql[] =
    "WITH p(k) AS (VALUES(?1)) SELECT * FROM ("
    "SELECT 'work_occurrence','work_id',CAST(e.target_work_id AS TEXT),'OUT '||e.relation||'['||e.position||'] -> #'||e.target_work_id||' '||n.kind FROM work_edge e JOIN work_occurrence n ON n.work_id=e.target_work_id,p WHERE e.source_work_id=CAST(p.k AS INTEGER) UNION ALL "
    "SELECT 'work_occurrence','work_id',CAST(e.source_work_id AS TEXT),'IN '||e.relation||'['||e.position||'] <- #'||e.source_work_id||' '||n.kind FROM work_edge e JOIN work_occurrence n ON n.work_id=e.source_work_id,p WHERE e.target_work_id=CAST(p.k AS INTEGER) UNION ALL "
    "SELECT 'model_attempt','request_id',a.request_id,'ATTEMPT '||a.state||' '||a.request_id FROM work_occurrence w JOIN model_attempt a ON a.request_id=w.request_id,p WHERE w.work_id=CAST(p.k AS INTEGER) AND w.request_id<>'' UNION ALL "
    "SELECT 'artifact','artifact_id',CAST(w.input_artifact_id AS TEXT),'INPUT artifact '||w.input_artifact_id FROM work_occurrence w,p WHERE w.work_id=CAST(p.k AS INTEGER) UNION ALL "
    "SELECT 'artifact','artifact_id',CAST(w.output_artifact_id AS TEXT),'OUTPUT artifact '||w.output_artifact_id FROM work_occurrence w,p WHERE w.work_id=CAST(p.k AS INTEGER) AND w.output_artifact_id IS NOT NULL UNION ALL "
    "SELECT 'worker_session','session_id',CAST(s.session_id AS TEXT),'WORKER gen='||s.generation||' '||s.state FROM work_occurrence w JOIN worker_session s ON s.request_id=w.request_id,p WHERE w.work_id=CAST(p.k AS INTEGER) AND w.request_id<>''"
    ") ORDER BY 4 LIMIT ?2 OFFSET ?3";
  static const char artifact_sql[] =
    "WITH p(k) AS (VALUES(?1)) SELECT * FROM ("
    "SELECT 'artifact','artifact_id',CAST(pr.predecessor_id AS TEXT),'PREDECESSOR['||pr.position||'] artifact '||pr.predecessor_id FROM predecessor pr,p WHERE pr.artifact_id=CAST(p.k AS INTEGER) UNION ALL "
    "SELECT 'artifact','artifact_id',CAST(pr.artifact_id AS TEXT),'SUCCESSOR from['||pr.position||'] artifact '||pr.artifact_id FROM predecessor pr,p WHERE pr.predecessor_id=CAST(p.k AS INTEGER) UNION ALL "
    "SELECT 'model_attempt','request_id',a.request_id,'MODEL INPUT '||a.request_id FROM model_attempt a,p WHERE a.input_artifact_id=CAST(p.k AS INTEGER) UNION ALL "
    "SELECT 'model_attempt','request_id',a.request_id,'MODEL OUTPUT '||a.request_id FROM model_attempt a,p WHERE a.output_artifact_id=CAST(p.k AS INTEGER)"
    ") ORDER BY 4 LIMIT ?2 OFFSET ?3";
  static const char attempt_sql[] =
    "WITH p(k) AS (VALUES(?1)) SELECT * FROM ("
    "SELECT 'worker_session','session_id',CAST(s.session_id AS TEXT),'WORKER gen='||s.generation||' '||s.state FROM worker_session s,p WHERE s.request_id=p.k UNION ALL "
    "SELECT 'artifact','artifact_id',CAST(a.input_artifact_id AS TEXT),'INPUT artifact '||a.input_artifact_id FROM model_attempt a,p WHERE a.request_id=p.k AND a.input_artifact_id IS NOT NULL UNION ALL "
    "SELECT 'artifact','artifact_id',CAST(a.output_artifact_id AS TEXT),'OUTPUT artifact '||a.output_artifact_id FROM model_attempt a,p WHERE a.request_id=p.k AND a.output_artifact_id IS NOT NULL UNION ALL "
    "SELECT 'model_attempt','request_id',a.request_id,'RESERVED output artifact '||a.reserved_output_artifact_id||' (not committed)' FROM model_attempt a,p WHERE a.request_id=p.k AND a.reserved_output_artifact_id IS NOT NULL UNION ALL "
    "SELECT 'conversation_event','event_id',CAST(e.event_id AS TEXT),'REQUEST EVENT '||e.event_id||' '||e.direction||' '||e.kind FROM conversation_event e,p WHERE e.request_id=p.k"
    ") ORDER BY 4 LIMIT ?2 OFFSET ?3";
  static const char session_sql[] =
    "WITH s AS (SELECT * FROM worker_session WHERE session_id=CAST(?1 AS INTEGER)), "
    "a AS (SELECT a.* FROM model_attempt a JOIN s ON s.request_id=a.request_id) "
    "SELECT * FROM ("
    "SELECT 'artifact' AS tab,'artifact_id' AS col,CAST(a.input_artifact_id AS TEXT) AS key,'MODEL INPUT artifact='||a.input_artifact_id AS label,0 AS grp,0 AS ts,0 AS eid "
    "FROM a WHERE a.input_artifact_id IS NOT NULL UNION ALL "
    "SELECT 'conversation_event','event_id',CAST(e.event_id AS TEXT),"
    "'#'||e.event_id||' '||CASE WHEN e.session_id=s.session_id AND (e.execution_id<>s.execution_id OR (e.request_id<>'' AND e.request_id<>s.request_id)) THEN '[!] ' "
    "WHEN e.session_id=s.session_id THEN '[S] ' WHEN e.request_id=s.request_id THEN '[R?] ' ELSE '[T?] ' END "
    "||e.direction||' '||e.kind||CASE WHEN e.rpc_id='' THEN '' ELSE ' rpc='||e.rpc_id END,1,e.timestamp_ns,e.event_id "
    "FROM conversation_event e,s WHERE e.session_id=s.session_id OR "
    "(e.session_id IS NULL AND e.request_id=s.request_id AND e.execution_id=s.execution_id "
    "AND (SELECT COUNT(*) FROM worker_session x WHERE x.request_id=s.request_id)=1) OR "
    "(e.session_id IS NULL AND s.thread_id<>'' AND e.thread_id=s.thread_id AND e.execution_id=s.execution_id AND "
    "(e.request_id='' OR e.request_id=s.request_id) AND (SELECT COUNT(*) FROM worker_session x WHERE x.execution_id=s.execution_id AND x.thread_id=s.thread_id)=1) UNION ALL "
    "SELECT 'artifact','artifact_id',CAST(a.output_artifact_id AS TEXT),'MODEL OUTPUT artifact='||a.output_artifact_id,2,0,0 "
    "FROM a WHERE a.output_artifact_id IS NOT NULL) ORDER BY grp,eid LIMIT ?2 OFFSET ?3";
  static const char events_sql[] =
    "SELECT 'conversation_event','event_id',CAST(event_id AS TEXT),direction||' '||kind||' event='||event_id||' request='||request_id "
    "FROM conversation_event ORDER BY timestamp_ns,event_id LIMIT ?1 OFFSET ?2";
  static const char failures_sql[] =
    "SELECT * FROM ("
    "SELECT 'run_metadata','singleton','1','RUN status='||status FROM run_metadata WHERE status IN ('failed','interrupted') UNION ALL "
    "SELECT 'checkpoint','singleton','1','CHECKPOINT status='||status FROM checkpoint WHERE status IN ('failed','interrupted') UNION ALL "
    "SELECT 'model_attempt','request_id',request_id,'ATTEMPT failed '||request_id FROM model_attempt WHERE state='sasFailed' UNION ALL "
    "SELECT 'worker_session','session_id',CAST(session_id AS TEXT),'WORKER '||state||' session='||session_id FROM worker_session WHERE state IN ('failed','interrupted') UNION ALL "
    "SELECT 'conversation_event','event_id',CAST(event_id AS TEXT),'WRITE '||write_state||' event='||event_id FROM conversation_event WHERE write_state IN ('write_raised','outcome_unknown')"
    ") ORDER BY 4 LIMIT ?1 OFFSET ?2";

  switch (view->kind) {
    case view_graph: return load_work_nodes(ui, view->offset, items);
    case view_node: return load_query(ui, node_sql, view->parent.key, 1, view->offset, items);
    case view_artifact: return load_query(ui, artifact_sql, view->parent.key, 1, view->offset, items);
    case view_attempt: return load_query(ui, attempt_sql, view->parent.key, 1, view->offset, items);
    case view_session: return load_query(ui, session_sql, view->parent.key, 1, view->offset, items);
    case view_events: return load_query(ui, events_sql, NULL, 0, view->offset, items);
    case view_failures: return load_query(ui, failures_sql, NULL, 0, view->offset, items);
    case view_tables: {
      int count = 0;
      int seen = 0;
      int total = current_table_count + (table_exists(ui->db, "artifact_file") ? 1 : 0);
      for (int i = 0; i < total && count < PAGE_SIZE; ++i) {
        int index = i < current_table_count ? i : current_table_count;
        if (!table_exists(ui->db, table_names[index])) continue;
        if (seen++ < view->offset) continue;
        item_set(&items[count++], "", "", table_names[index], table_names[index]);
      }
      return count;
    }
    case view_table_rows: return load_table_rows(ui, view, items);
    case view_event_detail:
      item_set(&items[0], "conversation_event", "event_id", view->parent.key, "selected event");
      return 1;
  }
  return 0;
}

static void push_view(Ui *ui, ViewKind kind, const Item *parent) {
  if (ui->depth + 1 >= MAX_DEPTH) {
    snprintf(ui->status, sizeof(ui->status), "navigation depth limit reached");
    return;
  }
  View *view = &ui->views[++ui->depth];
  memset(view, 0, sizeof(*view));
  view->kind = kind;
  view->selected = -1;
  ui->details_focused = false;
  if (parent) view->parent = *parent;
}

static void open_item(Ui *ui, const Item *item) {
  if (!item) return;
  if (!item->table[0]) {
    int index = table_index(item->key);
    if (index >= 0) {
      push_view(ui, view_table_rows, item);
      ui->views[ui->depth].table_index = index;
      ui->views[ui->depth].selected = 0;
    }
    return;
  }
  if (strcmp(item->table, "work_occurrence") == 0)
    push_view(ui, view_node, item);
  else if (strcmp(item->table, "artifact") == 0)
    push_view(ui, view_artifact, item);
  else if (strcmp(item->table, "model_attempt") == 0)
    push_view(ui, view_attempt, item);
  else if (strcmp(item->table, "worker_session") == 0)
    push_view(ui, view_session, item);
  else if (strcmp(item->table, "conversation_event") == 0)
    push_view(ui, view_event_detail, item);
}

static void enter_selected(Ui *ui) {
  View *view = &ui->views[ui->depth];
  Item item = selected_item(ui, view);
  if (view->kind == view_graph) {
    if (item.table[0]) open_item(ui, &item);
    return;
  }
  if (view->kind == view_table_rows) return; /* The selected row is already in the detail pane. */
  if (view->kind == view_tables) {
    int index = table_index(item.key);
    if (index >= 0) {
      push_view(ui, view_table_rows, &item);
      ui->views[ui->depth].table_index = index;
      ui->views[ui->depth].selected = 0;
    }
  } else if (view->kind == view_event_detail) {
    return;
  } else {
    open_item(ui, &item);
  }
}

static void open_session(Ui *ui, const char *session_id) {
  Item worker;
  item_set(&worker, "worker_session", "session_id", session_id, "worker session");
  push_view(ui, view_session, &worker);
}

static void open_session_artifact(Ui *ui, bool output) {
  View *view = &ui->views[ui->depth];
  if (view->kind != view_session) return;
  const char *column = output ? "output_artifact_id" : "input_artifact_id";
  char sql[256];
  snprintf(sql, sizeof(sql),
      "SELECT a.%s FROM worker_session s JOIN model_attempt a USING(request_id) WHERE s.session_id=?1", column);
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
  sqlite3_bind_int64(stmt, 1, strtoll(view->parent.key, NULL, 10));
  if (sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_type(stmt, 0) != SQLITE_NULL) {
    char key[64]; snprintf(key, sizeof(key), "%" PRId64, sqlite3_column_int64(stmt, 0));
    Item artifact; item_set(&artifact, "artifact", "artifact_id", key,
        output ? "model output artifact" : "model input artifact");
    sqlite3_finalize(stmt);
    push_view(ui, view_artifact, &artifact);
    return;
  }
  sqlite3_finalize(stmt);
  snprintf(ui->status, sizeof(ui->status), "no recorded %s artifact", output ? "output" : "input");
}

static bool open_latest_session_for_request(Ui *ui, const char *request_id) {
  sqlite3_stmt *stmt = NULL;
  static const char sql[] =
    "SELECT session_id FROM worker_session WHERE request_id=?1 ORDER BY generation DESC LIMIT 1";
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
  sqlite3_bind_text(stmt, 1, request_id, -1, SQLITE_TRANSIENT);
  bool found = sqlite3_step(stmt) == SQLITE_ROW;
  char id[64] = "";
  if (found) snprintf(id, sizeof(id), "%" PRId64, sqlite3_column_int64(stmt, 0));
  sqlite3_finalize(stmt);
  if (found) open_session(ui, id);
  return found;
}

static void open_conversation_for_work(Ui *ui, const Item *work) {
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(ui->db,
      "SELECT request_id FROM work_occurrence WHERE work_id=?1",
      -1, &stmt, NULL) != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "conversation lookup failed: %.400s", sqlite_error(ui->db));
    return;
  }
  sqlite3_bind_int64(stmt, 1, strtoll(work->key, NULL, 10));
  int rc = sqlite3_step(stmt);
  if (rc != SQLITE_ROW || sqlite3_column_type(stmt, 0) == SQLITE_NULL ||
      !sqlite3_column_text(stmt, 0) || !sqlite3_column_text(stmt, 0)[0]) {
    snprintf(ui->status, sizeof(ui->status), "work #%s has no model request", work->key);
    sqlite3_finalize(stmt);
    return;
  }
  const char *request = (const char *)sqlite3_column_text(stmt, 0);
  char request_id[MAX_KEY];
  snprintf(request_id, sizeof(request_id), "%s", request ? request : "");
  sqlite3_finalize(stmt);
  if (open_latest_session_for_request(ui, request_id)) return;
  Item attempt;
  item_set(&attempt, "model_attempt", "request_id", request_id, "model attempt");
  push_view(ui, view_attempt, &attempt);
  snprintf(ui->status, sizeof(ui->status), "attempt has no worker session yet; inspect its input and state");
}

static void open_conversation(Ui *ui) {
  View *view = &ui->views[ui->depth];
  if (view->kind == view_graph) {
    Item item = selected_item(ui, view);
    if (item.table[0]) open_conversation_for_work(ui, &item);
  } else if (view->kind == view_attempt) {
    if (!open_latest_session_for_request(ui, view->parent.key))
      snprintf(ui->status, sizeof(ui->status), "this attempt has no worker session; its input remains available here");
  } else {
    Item item = selected_item(ui, view);
    if (strcmp(item.table, "worker_session") == 0) open_session(ui, item.key);
    else if (strcmp(item.table, "model_attempt") == 0) {
      if (!open_latest_session_for_request(ui, item.key))
        snprintf(ui->status, sizeof(ui->status), "this attempt has no worker session");
    } else snprintf(ui->status, sizeof(ui->status),
        "select a model occurrence, attempt, or worker session first");
  }
}

static void inspect_graph_focus(Ui *ui) {
  View *view = &ui->views[ui->depth];
  Item focus = selected_item(ui, view);
  if (focus.table[0]) push_view(ui, view_node, &focus);
}

static void switch_worker_generation(Ui *ui, int direction) {
  View *view = &ui->views[ui->depth];
  if (view->kind != view_session) return;
  sqlite3_stmt *stmt = NULL;
  static const char sql[] =
    "SELECT s.request_id,s.generation FROM worker_session s WHERE s.session_id=?1";
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
  sqlite3_bind_int64(stmt, 1, strtoll(view->parent.key, NULL, 10));
  if (sqlite3_step(stmt) != SQLITE_ROW) { sqlite3_finalize(stmt); return; }
  char request[MAX_KEY];
  snprintf(request, sizeof(request), "%s", sqlite3_column_text(stmt, 0) ?
      (const char *)sqlite3_column_text(stmt, 0) : "");
  int generation = sqlite3_column_int(stmt, 1);
  sqlite3_finalize(stmt);
  const char *query = direction > 0 ?
      "SELECT session_id FROM worker_session WHERE request_id=?1 AND generation>?2 ORDER BY generation LIMIT 1" :
      "SELECT session_id FROM worker_session WHERE request_id=?1 AND generation<?2 ORDER BY generation DESC LIMIT 1";
  if (sqlite3_prepare_v2(ui->db, query, -1, &stmt, NULL) != SQLITE_OK) return;
  sqlite3_bind_text(stmt, 1, request, -1, SQLITE_TRANSIENT);
  sqlite3_bind_int(stmt, 2, generation);
  if (sqlite3_step(stmt) == SQLITE_ROW) {
    char id[64]; snprintf(id, sizeof(id), "%" PRId64, sqlite3_column_int64(stmt, 0));
    item_set(&view->parent, "worker_session", "session_id", id, "worker session");
    view->selected = -1;
    view->offset = 0;
    view->detail_scroll = 0;
    ui->page_count = 0;
  } else snprintf(ui->status, sizeof(ui->status), "no earlier/later worker generation");
  sqlite3_finalize(stmt);
}

static bool read_header(Ui *ui) {
  sqlite3_stmt *stmt = NULL;
  static const char sql[] =
    "SELECT r.run_id,r.workflow_id,r.status,COALESCE(c.sequence,-1),COALESCE(c.status,'none'),"
    "COALESCE(r.active_execution_id,0),COALESCE(e.heartbeat_at_ns,0),COALESCE(e.ended_at_ns,0),"
    "(SELECT COUNT(DISTINCT s.session_id) FROM worker_session s JOIN model_attempt a USING(request_id) "
    "JOIN run_execution x ON x.execution_id=s.execution_id WHERE s.execution_id=r.active_execution_id "
    "AND x.ended_at_ns=0 AND r.status='running' AND s.state IN ('starting','working') "
    "AND a.state NOT IN ('sasCommitted','sasFailed') AND x.heartbeat_at_ns BETWEEN ?1-6000000000 AND ?1) "
    "FROM run_metadata r LEFT JOIN checkpoint c ON c.singleton=1 "
    "LEFT JOIN run_execution e ON e.execution_id=r.active_execution_id WHERE r.singleton=1";
  ui->now_ns = wall_time_ns();
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) return false;
  sqlite3_bind_int64(stmt, 1, ui->now_ns);
  if (sqlite3_step(stmt) != SQLITE_ROW) { sqlite3_finalize(stmt); return false; }
  const char *run_id = (const char *)sqlite3_column_text(stmt, 0);
  const char *status = (const char *)sqlite3_column_text(stmt, 2);
  int64_t sequence = sqlite3_column_int64(stmt, 3);
  const char *checkpoint_status = (const char *)sqlite3_column_text(stmt, 4);
  int64_t execution_id = sqlite3_column_int64(stmt, 5);
  int64_t heartbeat = sqlite3_column_int64(stmt, 6);
  int64_t ended = sqlite3_column_int64(stmt, 7);
  int active_workers = sqlite3_column_int(stmt, 8);
  int64_t age = heartbeat > 0 && ui->now_ns >= heartbeat ? (ui->now_ns-heartbeat)/1000000000LL : -1;
  if (age >= 0)
    snprintf(ui->header, sizeof(ui->header),
        "ACTIVE=%d | RUN %.36s %.16s | exec=%" PRId64 " %s | hb=%" PRId64 "s | cp=%" PRId64 "/%.12s",
        active_workers, run_id ? run_id : "?", status ? status : "?", execution_id,
        execution_id == 0 ? "none" : (ended == 0 ? "end=0" : "ended"), age,
        sequence, checkpoint_status ? checkpoint_status : "?");
  else
    snprintf(ui->header, sizeof(ui->header),
        "ACTIVE=%d | RUN %.36s %.16s | exec=%" PRId64 " %s | hb=unknown | cp=%" PRId64 "/%.12s",
        active_workers, run_id ? run_id : "?", status ? status : "?", execution_id,
        execution_id == 0 ? "none" : (ended == 0 ? "end=0" : "ended"),
        sequence, checkpoint_status ? checkpoint_status : "?");
  sqlite3_finalize(stmt);
  return true;
}

typedef struct {
  const char *input;
  size_t input_len;
  size_t pos;
  char *output;
  size_t output_len;
  size_t output_cap;
} JsonPretty;

static bool json_append(JsonPretty *json, const char *text, size_t length) {
  if (length > SIZE_MAX - json->output_len - 1) return false;
  size_t needed = json->output_len + length + 1;
  if (needed > json->output_cap) {
    size_t capacity = json->output_cap ? json->output_cap : 128;
    while (capacity < needed) {
      if (capacity > SIZE_MAX / 2) { capacity = needed; break; }
      capacity *= 2;
    }
    char *grown = realloc(json->output, capacity);
    if (!grown) return false;
    json->output = grown;
    json->output_cap = capacity;
  }
  memcpy(json->output + json->output_len, text, length);
  json->output_len += length;
  json->output[json->output_len] = '\0';
  return true;
}

static bool json_char(JsonPretty *json, char value) {
  return json_append(json, &value, 1);
}

static void json_skip_space(JsonPretty *json) {
  while (json->pos < json->input_len &&
      (json->input[json->pos] == ' ' || json->input[json->pos] == '\t' ||
       json->input[json->pos] == '\r' || json->input[json->pos] == '\n'))
    json->pos++;
}

static bool json_indent(JsonPretty *json, int depth) {
  if (!json_char(json, '\n')) return false;
  for (int i = 0; i < depth * 2; ++i)
    if (!json_char(json, ' ')) return false;
  return true;
}

static bool json_parse_value(JsonPretty *json, int depth);

static bool json_parse_string(JsonPretty *json) {
  if (json->pos >= json->input_len || json->input[json->pos] != '"') return false;
  size_t start = json->pos++;
  while (json->pos < json->input_len) {
    unsigned char ch = (unsigned char)json->input[json->pos++];
    if (ch == '"')
      return json_append(json, json->input + start, json->pos - start);
    if (ch < 0x20) return false;
    if (ch == '\\') {
      if (json->pos >= json->input_len) return false;
      char escape = json->input[json->pos++];
      if (escape == 'u') {
        for (int i = 0; i < 4; ++i) {
          if (json->pos >= json->input_len ||
              !((json->input[json->pos] >= '0' && json->input[json->pos] <= '9') ||
                (json->input[json->pos] >= 'a' && json->input[json->pos] <= 'f') ||
                (json->input[json->pos] >= 'A' && json->input[json->pos] <= 'F')))
            return false;
          json->pos++;
        }
      } else if (escape != '"' && escape != '\\' && escape != '/' &&
          escape != 'b' && escape != 'f' && escape != 'n' &&
          escape != 'r' && escape != 't') return false;
    }
  }
  return false;
}

static bool json_parse_number(JsonPretty *json) {
  size_t start = json->pos;
  if (json->input[json->pos] == '-') json->pos++;
  if (json->pos >= json->input_len) return false;
  if (json->input[json->pos] == '0') {
    json->pos++;
    if (json->pos < json->input_len && json->input[json->pos] >= '0' &&
        json->input[json->pos] <= '9') return false;
  } else {
    if (json->input[json->pos] < '1' || json->input[json->pos] > '9') return false;
    while (json->pos < json->input_len && json->input[json->pos] >= '0' &&
        json->input[json->pos] <= '9') json->pos++;
  }
  if (json->pos < json->input_len && json->input[json->pos] == '.') {
    json->pos++;
    size_t digits = json->pos;
    while (json->pos < json->input_len && json->input[json->pos] >= '0' &&
        json->input[json->pos] <= '9') json->pos++;
    if (digits == json->pos) return false;
  }
  if (json->pos < json->input_len &&
      (json->input[json->pos] == 'e' || json->input[json->pos] == 'E')) {
    json->pos++;
    if (json->pos < json->input_len &&
        (json->input[json->pos] == '+' || json->input[json->pos] == '-')) json->pos++;
    size_t digits = json->pos;
    while (json->pos < json->input_len && json->input[json->pos] >= '0' &&
        json->input[json->pos] <= '9') json->pos++;
    if (digits == json->pos) return false;
  }
  return json_append(json, json->input + start, json->pos - start);
}

static bool json_parse_literal(JsonPretty *json, const char *literal) {
  size_t length = strlen(literal);
  if (length > json->input_len - json->pos ||
      memcmp(json->input + json->pos, literal, length) != 0) return false;
  json->pos += length;
  return json_append(json, literal, length);
}

static bool json_parse_object(JsonPretty *json, int depth) {
  if (depth >= 128 || !json_char(json, '{')) return false;
  json->pos++;
  json_skip_space(json);
  if (json->pos < json->input_len && json->input[json->pos] == '}') {
    json->pos++;
    return json_char(json, '}');
  }
  for (;;) {
    if (!json_indent(json, depth + 1) || !json_parse_string(json)) return false;
    json_skip_space(json);
    if (json->pos >= json->input_len || json->input[json->pos++] != ':' ||
        !json_append(json, ": ", 2)) return false;
    json_skip_space(json);
    if (!json_parse_value(json, depth + 1)) return false;
    json_skip_space(json);
    if (json->pos >= json->input_len) return false;
    if (json->input[json->pos] == ',') {
      json->pos++;
      if (!json_char(json, ',')) return false;
      json_skip_space(json);
      continue;
    }
    if (json->input[json->pos] != '}') return false;
    json->pos++;
    return json_indent(json, depth) && json_char(json, '}');
  }
}

static bool json_parse_array(JsonPretty *json, int depth) {
  if (depth >= 128 || !json_char(json, '[')) return false;
  json->pos++;
  json_skip_space(json);
  if (json->pos < json->input_len && json->input[json->pos] == ']') {
    json->pos++;
    return json_char(json, ']');
  }
  for (;;) {
    if (!json_indent(json, depth + 1) || !json_parse_value(json, depth + 1)) return false;
    json_skip_space(json);
    if (json->pos >= json->input_len) return false;
    if (json->input[json->pos] == ',') {
      json->pos++;
      if (!json_char(json, ',')) return false;
      json_skip_space(json);
      continue;
    }
    if (json->input[json->pos] != ']') return false;
    json->pos++;
    return json_indent(json, depth) && json_char(json, ']');
  }
}

static bool json_parse_value(JsonPretty *json, int depth) {
  json_skip_space(json);
  if (json->pos >= json->input_len) return false;
  switch (json->input[json->pos]) {
    case '{': return json_parse_object(json, depth);
    case '[': return json_parse_array(json, depth);
    case '"': return json_parse_string(json);
    case 't': return json_parse_literal(json, "true");
    case 'f': return json_parse_literal(json, "false");
    case 'n': return json_parse_literal(json, "null");
    default:
      if (json->input[json->pos] == '-' ||
          (json->input[json->pos] >= '0' && json->input[json->pos] <= '9'))
        return json_parse_number(json);
      return false;
  }
}

static char *pretty_json(const char *input) {
  JsonPretty json = {0};
  json.input = input;
  json.input_len = strlen(input);
  if (!json_parse_value(&json, 0)) { free(json.output); return NULL; }
  json_skip_space(&json);
  if (json.pos != json.input_len) { free(json.output); return NULL; }
  return json.output;
}

/* Small read-only JSON cursor used by the transcript and node details. It
   walks nested JSON without storing a tree or depending on SQLite extensions. */
typedef struct { const char *s; size_t n, p; } JsonCursor;
typedef struct { size_t a, b; } JsonSpan;

static void json_ws(JsonCursor *c) {
  while (c->p < c->n && (c->s[c->p] == ' ' || c->s[c->p] == '\n' ||
      c->s[c->p] == '\r' || c->s[c->p] == '\t')) c->p++;
}

static bool json_string_end(JsonCursor *c) {
  if (c->p >= c->n || c->s[c->p++] != '"') return false;
  while (c->p < c->n) {
    unsigned char ch = (unsigned char)c->s[c->p++];
    if (ch == '"') return true;
    if (ch < 0x20) return false;
    if (ch == '\\') {
      if (c->p >= c->n) return false;
      ch = (unsigned char)c->s[c->p++];
      if (ch == 'u') {
        for (int i = 0; i < 4; ++i) {
          if (c->p >= c->n || !((c->s[c->p] >= '0' && c->s[c->p] <= '9') ||
              (c->s[c->p] >= 'a' && c->s[c->p] <= 'f') ||
              (c->s[c->p] >= 'A' && c->s[c->p] <= 'F'))) return false;
          c->p++;
        }
      } else if (ch != '"' && ch != '\\' && ch != '/' && ch != 'b' &&
          ch != 'f' && ch != 'n' && ch != 'r' && ch != 't') return false;
    }
  }
  return false;
}

static bool json_value_end(JsonCursor *c, int depth) {
  if (depth > 64) return false;
  json_ws(c);
  if (c->p >= c->n) return false;
  char ch = c->s[c->p];
  if (ch == '"') return json_string_end(c);
  if (ch == '{' || ch == '[') {
    char close = ch == '{' ? '}' : ']';
    c->p++;
    json_ws(c);
    if (c->p < c->n && c->s[c->p] == close) { c->p++; return true; }
    for (;;) {
      if (ch == '{') {
        if (!json_string_end(c)) return false;
        json_ws(c);
        if (c->p >= c->n || c->s[c->p++] != ':') return false;
      }
      if (!json_value_end(c, depth + 1)) return false;
      json_ws(c);
      if (c->p >= c->n) return false;
      if (c->s[c->p] == close) { c->p++; return true; }
      if (c->s[c->p++] != ',') return false;
      json_ws(c);
    }
  }
  size_t start = c->p;
  while (c->p < c->n && c->s[c->p] != ',' && c->s[c->p] != ']' &&
      c->s[c->p] != '}' && c->s[c->p] != ' ' && c->s[c->p] != '\n' &&
      c->s[c->p] != '\r' && c->s[c->p] != '\t') c->p++;
  return c->p > start;
}

static bool json_key_equal(const char *s, size_t a, size_t b, const char *key) {
  size_t i = a + 1, j = 0, end = b - 1;
  while (i < end && key[j]) {
    if (s[i] == '\\' || (unsigned char)s[i] >= 0x80 || s[i] != key[j]) return false;
    i++; j++;
  }
  return i == end && key[j] == '\0';
}

static bool json_get(const char *s, JsonSpan object, const char *key, JsonSpan *out) {
  JsonCursor c = {s, strlen(s), object.a};
  json_ws(&c);
  if (c.p >= object.b || c.s[c.p++] != '{') return false;
  for (;;) {
    json_ws(&c);
    if (c.p >= object.b || c.s[c.p] == '}') return false;
    size_t ka = c.p;
    if (!json_string_end(&c)) return false;
    size_t kb = c.p;
    json_ws(&c);
    if (c.p >= object.b || c.s[c.p++] != ':') return false;
    json_ws(&c);
    size_t va = c.p;
    if (!json_value_end(&c, 0)) return false;
    size_t vb = c.p;
    if (json_key_equal(s, ka, kb, key)) { out->a = va; out->b = vb; return true; }
    json_ws(&c);
    if (c.p >= object.b || c.s[c.p++] != ',') return false;
  }
}

static uint32_t json_hex4(const char *s) {
  uint32_t value = 0;
  for (int i = 0; i < 4; ++i) {
    unsigned char c = (unsigned char)s[i];
    value = value * 16 + (c >= '0' && c <= '9' ? c - '0' :
        c >= 'a' && c <= 'f' ? c - 'a' + 10 : c - 'A' + 10);
  }
  return value;
}

static bool json_string_copy(const char *s, JsonSpan span, char *out, size_t cap) {
  if (!cap || span.a >= span.b || s[span.a] != '"') return false;
  size_t p = span.a + 1, n = 0, end = span.b - 1;
  while (p < end && n + 1 < cap) {
    unsigned char ch = (unsigned char)s[p++];
    if (ch == '\\' && p < end) {
      ch = (unsigned char)s[p++];
      switch (ch) {
        case 'n': ch = '\n'; break; case 'r': ch = '\r'; break;
        case 't': ch = '\t'; break; case 'b': ch = ' '; break;
        case 'f': ch = ' '; break;
        case 'u': {
          if (p + 4 > end) return false;
          uint32_t cp = json_hex4(s + p); p += 4;
          if (cp >= 0xd800 && cp <= 0xdbff && p + 6 <= end && s[p] == '\\' && s[p+1] == 'u') {
            uint32_t low = json_hex4(s + p + 2);
            if (low >= 0xdc00 && low <= 0xdfff) { cp = 0x10000 + ((cp-0xd800)<<10) + low-0xdc00; p += 6; }
          }
          if (cp >= 0xd800 && cp <= 0xdfff) cp = 0xfffd;
          unsigned char encoded[4]; size_t count;
          if (cp < 0x80) { encoded[0] = (unsigned char)cp; count = 1; }
          else if (cp < 0x800) { encoded[0] = 0xc0 | (cp >> 6); encoded[1] = 0x80 | (cp & 0x3f); count = 2; }
          else if (cp < 0x10000) { encoded[0] = 0xe0 | (cp >> 12); encoded[1] = 0x80 | ((cp >> 6) & 0x3f); encoded[2] = 0x80 | (cp & 0x3f); count = 3; }
          else { encoded[0] = 0xf0 | (cp >> 18); encoded[1] = 0x80 | ((cp >> 12) & 0x3f); encoded[2] = 0x80 | ((cp >> 6) & 0x3f); encoded[3] = 0x80 | (cp & 0x3f); count = 4; }
          if (n + count >= cap) { out[n] = '\0'; return true; }
          memcpy(out + n, encoded, count); n += count;
          continue;
        }
        default: break;
      }
    }
    out[n++] = ch < 0x20 ? ' ' : (char)ch;
  }
  out[n] = '\0';
  return true;
}

static bool json_member(const char *s, JsonSpan parent, const char *key,
    char *out, size_t cap) {
  JsonSpan value;
  return json_get(s, parent, key, &value) && json_string_copy(s, value, out, cap);
}

static int draw_value(int x, int y, int width, int height, const char *text,
    int scroll, int *line, uintattr_t fg) {
  size_t length = strlen(text), offset = 0;
  int col = 0;
  while (offset < length) {
    size_t used = 1;
    uint32_t cp = 0xfffd;
    decode_utf8(text + offset, length - offset, &used, &cp);
    offset += used;
    if (cp == '\n') { (*line)++; col = 0; continue; }
    if (cp == '\r') cp = '?';
    if (cp == '\t') cp = ' ';
    if (cp < 0x20 || cp == 0x7f) cp = '?';
    int cw = wcwidth((wchar_t)cp);
    if (cw < 1) { cp = 0xfffd; cw = 1; }
    if (col + cw > width) { (*line)++; col = 0; }
    if (*line >= scroll && *line - scroll < height)
      draw_codepoint(x + col, y + *line - scroll, cp, fg, UI_BG, x + width);
    col += cw;
  }
  (*line)++;
  return 0;
}

static bool draw_record(Ui *ui, const Item *item, int x, int y, int width,
    int height, int scroll) {
  char sql[256];
  sqlite3_stmt *stmt = NULL;
  if (!item || !item->table[0]) {
    draw_plain(x, y, width, "Select a row to inspect its stored fields", UI_FG, UI_BG);
    return true;
  }
  if (!table_exists(ui->db, item->table)) {
    draw_plain(x, y, width, "Record table not present", UI_GOLD, UI_BG);
    return true;
  }
  if (item->rowid_key)
    snprintf(sql, sizeof(sql), "SELECT * FROM \"%s\" WHERE rowid=?1", item->table);
  else
    snprintf(sql, sizeof(sql), "SELECT * FROM \"%s\" WHERE \"%s\"=?1",
        item->table, item->key_column);
  int rc = sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL);
  if (rc != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "detail read failed: %.440s", sqlite_error(ui->db));
    return false;
  }
  if (item->rowid_key) sqlite3_bind_int64(stmt, 1, strtoll(item->key, NULL, 10));
  else sqlite3_bind_text(stmt, 1, item->key, -1, SQLITE_TRANSIENT);
  rc = sqlite3_step(stmt);
  if (rc != SQLITE_ROW) {
    draw_plain(x, y, width, "Record not found", UI_GOLD, UI_BG);
    sqlite3_finalize(stmt);
    return true;
  }
  int line = 0;
  for (int i = 0; i < sqlite3_column_count(stmt); ++i) {
    char label[128];
    snprintf(label, sizeof(label), "%s:", sqlite3_column_name(stmt, i));
    if (line >= scroll && line - scroll < height)
      draw_plain(x, y + line - scroll, width, label, UI_TEAL, UI_BG);
    line++;
    const unsigned char *value = sqlite3_column_text(stmt, i);
    const char *raw = value ? (const char *)value : "NULL";
    char *formatted = value ? pretty_json(raw) : NULL;
    draw_value(x + 2, y, width - 2, height, formatted ? formatted : raw,
        scroll, &line, UI_FG);
    free(formatted);
  }
  sqlite3_finalize(stmt);
  return true;
}

static void draw_box(int x, int y, int width, int height) {
  if (width < 2 || height < 2) return;
  for (int col = 0; col < width; ++col) {
    tb_set_cell(x + col, y, col == 0 || col == width-1 ? '+' : '-', UI_BORDER, UI_BG);
    tb_set_cell(x + col, y + height-1, col == 0 || col == width-1 ? '+' : '-', UI_BORDER, UI_BG);
  }
  for (int row = 1; row < height-1; ++row) {
    tb_set_cell(x, y + row, '|', UI_BORDER, UI_BG);
    tb_set_cell(x + width-1, y + row, '|', UI_BORDER, UI_BG);
  }
}

static int current_list_count(Ui *ui, View *view) {
  Item previous;
  bool same_page = ui->page_valid && ui->page_depth == ui->depth &&
      ui->page_kind == view->kind;
  bool preserve = same_page && view->selected >= 0 && view->selected < ui->page_count;
  if (preserve) previous = ui->page[view->selected];
  int count = load_items_fixed(ui, view, ui->page);
  if (count < 0) return -1;
  ui->page_count = count;
  ui->page_depth = ui->depth;
  ui->page_kind = view->kind;
  ui->page_valid = true;
  if (preserve) {
    int match = -1;
    for (int i = 0; i < count; ++i) {
      if (strcmp(previous.table, ui->page[i].table) != 0 ||
          strcmp(previous.key, ui->page[i].key) != 0) continue;
      match = i;
      break;
    }
    if (match >= 0) view->selected = match;
    else if (count == 0) view->selected = -1;
    else {
      if (view->selected >= count) view->selected = count - 1;
      if (view->selected < 0) view->selected = 0;
      if (!ui->status[0])
        snprintf(ui->status, sizeof(ui->status), "selected record moved; showing nearest row");
    }
  } else if (view->selected >= count) view->selected = count - 1;
  if (!preserve && view->selected < 0 && count > 0) {
    view->selected = 0;
  }
  if (view->selected < -1) view->selected = -1;
  return count;
}

static bool focus_work_id(Ui *ui, int64_t work_id) {
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(ui->db,
      "SELECT COUNT(*) FROM work_occurrence WHERE work_id < ?1",
      -1, &stmt, NULL) != SQLITE_OK) return false;
  sqlite3_bind_int64(stmt, 1, work_id);
  if (sqlite3_step(stmt) != SQLITE_ROW) { sqlite3_finalize(stmt); return false; }
  int64_t rank = sqlite3_column_int64(stmt, 0);
  sqlite3_finalize(stmt);
  View *view = &ui->views[0];
  view->offset = (int)(rank / PAGE_SIZE) * PAGE_SIZE;
  view->selected = (int)(rank % PAGE_SIZE);
  view->detail_scroll = 0;
  view->graph_reveal_selection = true;
  ui->details_focused = false;
  ui->page_valid = false;
  ui->status[0] = '\0';
  return true;
}

static bool graph_follow_neighbor(Ui *ui, bool outgoing, int delta) {
  View *view = &ui->views[0];
  Item focus = selected_item(ui, view);
  if (strcmp(focus.table, "work_occurrence") != 0) return false;
  int64_t focused_id = strtoll(focus.key, NULL, 10);
  if (delta == 0 || !view->graph_neighbor_ready ||
      view->graph_neighbor_outgoing != outgoing) {
    view->graph_neighbor_origin = focused_id;
    view->graph_neighbor_index = delta > 0 ? SIZE_MAX : 0;
    view->graph_neighbor_ready = true;
  }
  int64_t source_id = view->graph_neighbor_origin;
  sqlite3_stmt *stmt = NULL;
  const char *count_sql = outgoing ?
      "SELECT COUNT(*) FROM work_edge WHERE source_work_id=?1" :
      "SELECT COUNT(*) FROM work_edge WHERE target_work_id=?1";
  if (sqlite3_prepare_v2(ui->db, count_sql, -1, &stmt, NULL) != SQLITE_OK) return false;
  sqlite3_bind_int64(stmt, 1, source_id);
  if (sqlite3_step(stmt) != SQLITE_ROW) { sqlite3_finalize(stmt); return false; }
  int count = sqlite3_column_int(stmt, 0);
  sqlite3_finalize(stmt);
  if (!count) {
    snprintf(ui->status, sizeof(ui->status), "work #%s has no %s edges",
        focus.key, outgoing ? "outgoing" : "incoming");
    return false;
  }
  if (delta != 0) {
    if (view->graph_neighbor_index == SIZE_MAX)
      view->graph_neighbor_index = 0;
    else {
      int current = (int)view->graph_neighbor_index + delta;
      if (current < 0) current = count - 1;
      if (current >= count) current = 0;
      view->graph_neighbor_index = (size_t)current;
    }
  }
  view->graph_neighbor_outgoing = outgoing;
  if (view->graph_neighbor_index >= (size_t)count) view->graph_neighbor_index = 0;
  const char *target_sql = outgoing ?
      "SELECT target_work_id FROM work_edge WHERE source_work_id=?1 ORDER BY relation,position,target_work_id LIMIT 1 OFFSET ?2" :
      "SELECT source_work_id FROM work_edge WHERE target_work_id=?1 ORDER BY relation,position,source_work_id LIMIT 1 OFFSET ?2";
  if (sqlite3_prepare_v2(ui->db, target_sql, -1, &stmt, NULL) != SQLITE_OK) return false;
  sqlite3_bind_int64(stmt, 1, source_id);
  sqlite3_bind_int64(stmt, 2, (sqlite3_int64)view->graph_neighbor_index);
  bool found = sqlite3_step(stmt) == SQLITE_ROW;
  int64_t target = found ? sqlite3_column_int64(stmt, 0) : 0;
  sqlite3_finalize(stmt);
  if (!found || !focus_work_id(ui, target)) return false;
  return true;
}

static void graph_cycle_neighbor(Ui *ui, bool outgoing) {
  (void)graph_follow_neighbor(ui, outgoing, 1);
}

static void draw_work_field(int x, int y, int width, int height, int scroll,
    int *line, const char *label, const char *value) {
  if (*line >= scroll && *line - scroll < height)
    draw_plain(x, y + *line - scroll, width, label, UI_TEAL, UI_BG);
  (*line)++;
  (void)draw_value(x + 2, y, width - 2, height, value, scroll, line, UI_FG);
}

static void draw_work_edges(Ui *ui, int64_t id, bool outgoing, int x, int y,
    int width, int height, int scroll, int *line) {
  sqlite3_stmt *stmt = NULL;
  const char *sql = outgoing ?
      "SELECT e.relation,e.position,w.work_id,w.kind FROM work_edge e JOIN work_occurrence w ON w.work_id=e.target_work_id WHERE e.source_work_id=?1 ORDER BY e.relation,e.position,w.work_id" :
      "SELECT e.relation,e.position,w.work_id,w.kind FROM work_edge e JOIN work_occurrence w ON w.work_id=e.source_work_id WHERE e.target_work_id=?1 ORDER BY e.relation,e.position,w.work_id";
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
  sqlite3_bind_int64(stmt, 1, id);
  if (*line >= scroll && *line - scroll < height)
    draw_plain(x, y + *line - scroll, width, outgoing ? "Outgoing:" : "Incoming:", UI_TEAL, UI_BG);
  (*line)++;
  int count = 0, rc;
  while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
    char item[512];
    const char *relation = (const char *)sqlite3_column_text(stmt, 0);
    const char *kind = (const char *)sqlite3_column_text(stmt, 3);
    snprintf(item, sizeof(item), "%s[%d] %s #%" PRId64 " %c",
        relation ? relation : "?", sqlite3_column_int(stmt, 1),
        outgoing ? "→" : "←", sqlite3_column_int64(stmt, 2),
        work_glyph(kind ? kind : ""));
    (void)draw_value(x + 2, y, width - 2, height, item, scroll, line, UI_FG);
    count++;
  }
  if (rc == SQLITE_DONE && count == 0) {
    if (*line >= scroll && *line - scroll < height)
      draw_plain(x + 2, y + *line - scroll, width - 2, "(none)", UI_IDLE, UI_BG);
    (*line)++;
  }
  sqlite3_finalize(stmt);
}

static void draw_work_dag_detail(Ui *ui, const Item *item, int x, int y,
    int width, int height, int scroll) {
  sqlite3_stmt *stmt = NULL;
  static const char sql[] =
    "SELECT work_id,flow_key,kind,state,input_artifact_id,output_artifact_id,request_id,expansion_id,join_id,root_name,slot "
    "FROM work_occurrence WHERE work_id=?1";
  if (!item || strcmp(item->table, "work_occurrence") != 0) {
    draw_plain(x, y, width, ui->schema_version == 7 ?
        "Schema 7 has no occurrence history; use a schema 8 run." :
        "No work occurrence selected", UI_GOLD, UI_BG);
    return;
  }
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) {
    draw_plain(x, y, width, "DAG detail read failed", UI_FAILED, UI_BG);
    return;
  }
  sqlite3_bind_int64(stmt, 1, strtoll(item->key, NULL, 10));
  if (sqlite3_step(stmt) != SQLITE_ROW) {
    sqlite3_finalize(stmt);
    draw_plain(x, y, width, "Occurrence no longer exists", UI_GOLD, UI_BG);
    return;
  }
  int64_t id = sqlite3_column_int64(stmt, 0);
  char flow_key[MAX_KEY], kind[32], state[32], request[MAX_KEY], root[MAX_KEY];
  snprintf(flow_key, sizeof(flow_key), "%s", sqlite3_column_text(stmt, 1) ? (const char *)sqlite3_column_text(stmt, 1) : "");
  snprintf(kind, sizeof(kind), "%s", sqlite3_column_text(stmt, 2) ? (const char *)sqlite3_column_text(stmt, 2) : "?");
  snprintf(state, sizeof(state), "%s", sqlite3_column_text(stmt, 3) ? (const char *)sqlite3_column_text(stmt, 3) : "?");
  int64_t input = sqlite3_column_int64(stmt, 4);
  bool has_output = sqlite3_column_type(stmt, 5) != SQLITE_NULL;
  int64_t output = has_output ? sqlite3_column_int64(stmt, 5) : 0;
  snprintf(request, sizeof(request), "%s", sqlite3_column_text(stmt, 6) ? (const char *)sqlite3_column_text(stmt, 6) : "");
  int64_t expansion = sqlite3_column_int64(stmt, 7);
  int64_t join = sqlite3_column_int64(stmt, 8);
  snprintf(root, sizeof(root), "%s", sqlite3_column_text(stmt, 9) ? (const char *)sqlite3_column_text(stmt, 9) : "");
  int slot = sqlite3_column_int(stmt, 10);
  sqlite3_finalize(stmt);

  bool active = request[0] && live_model_request(ui, request);
  const char *shown_state = active ? "active" : state;
  int line = 0;
  char value[2048];
  snprintf(value, sizeof(value), "WORK #%-6" PRId64 " %c %s", id,
      work_glyph(kind), shown_state);
  if (line >= scroll && line - scroll < height)
    draw_plain(x, y + line - scroll, width, value,
        (strcmp(shown_state, "running") == 0 || active) ? UI_GOLD :
        strcmp(shown_state, "failed") == 0 ? UI_FAILED :
        strcmp(shown_state, "completed") == 0 ? UI_GREEN : UI_FG, UI_BG);
  line++;
  if (active) draw_work_field(x, y, width, height, scroll, &line,
      "Scheduler state:", state);
  draw_work_field(x, y, width, height, scroll, &line, "Flow key:", flow_key);
  if (root[0]) draw_work_field(x, y, width, height, scroll, &line, "Reference target:", root);
  snprintf(value, sizeof(value), "%" PRId64, input);
  draw_work_field(x, y, width, height, scroll, &line, "Input artifact:", value);
  snprintf(value, sizeof(value), "%" PRId64, output);
  draw_work_field(x, y, width, height, scroll, &line, "Output artifact:", has_output ? value : "(pending)");
  draw_work_field(x, y, width, height, scroll, &line, "Model request:", request[0] ? request : "(none)");
  if (expansion) { snprintf(value, sizeof(value), "%" PRId64, expansion); draw_work_field(x, y, width, height, scroll, &line, "SO expansion:", value); }
  if (join) { snprintf(value, sizeof(value), "%" PRId64, join); draw_work_field(x, y, width, height, scroll, &line, "Join:", value); }
  if (slot >= 0) { snprintf(value, sizeof(value), "%d", slot); draw_work_field(x, y, width, height, scroll, &line, "Slot:", value); }
  draw_work_edges(ui, id, false, x, y, width, height, scroll, &line);
  draw_work_edges(ui, id, true, x, y, width, height, scroll, &line);
}

static bool reserve_items(void **items, size_t *capacity, size_t needed,
    size_t item_size) {
  if (needed <= *capacity) return true;
  if (item_size == 0 || needed > SIZE_MAX / item_size) return false;
  size_t next = *capacity ? *capacity : 16;
  while (next < needed) {
    if (next > SIZE_MAX / 2) { next = needed; break; }
    next *= 2;
  }
  if (next > SIZE_MAX / item_size) return false;
  void *grown = realloc(*items, next * item_size);
  if (!grown) return false;
  *items = grown;
  *capacity = next;
  return true;
}

static void dag_layout_free(DagLayout *dag) {
  free(dag->nodes);
  free(dag->edges);
  free(dag->points);
  free(dag->segments);
  free(dag->paths);
  free(dag->layer_order);
  free(dag->layers);
  memset(dag, 0, sizeof(*dag));
}

static size_t dag_node_index(const DagLayout *dag, int64_t id) {
  size_t lo = 0, hi = dag->node_count;
  while (lo < hi) {
    size_t mid = lo + (hi - lo) / 2;
    if (dag->nodes[mid].id < id) lo = mid + 1;
    else hi = mid;
  }
  return lo < dag->node_count && dag->nodes[lo].id == id ? lo : SIZE_MAX;
}

static DagPoint *dag_sort_points;

static int compare_dag_points(const void *left, const void *right) {
  size_t a = *(const size_t *)left, b = *(const size_t *)right;
  if (dag_sort_points[a].score < dag_sort_points[b].score) return -1;
  if (dag_sort_points[a].score > dag_sort_points[b].score) return 1;
  if (dag_sort_points[a].stable < dag_sort_points[b].stable) return -1;
  if (dag_sort_points[a].stable > dag_sort_points[b].stable) return 1;
  return 0;
}

static void dag_barycenter_pass(DagLayout *dag, bool downward) {
  for (size_t i = 0; i < dag->point_count; ++i) {
    dag->points[i].score = 0.0;
    dag->points[i].samples = 0;
  }
  for (size_t i = 0; i < dag->segment_count; ++i) {
    DagPoint *from = &dag->points[dag->segments[i].source];
    DagPoint *to = &dag->points[dag->segments[i].target];
    DagPoint *point = downward ? to : from;
    DagPoint *neighbor = downward ? from : to;
    point->score += (double)neighbor->order;
    point->samples++;
  }
  for (size_t i = 0; i < dag->point_count; ++i) {
    if (dag->points[i].samples)
      dag->points[i].score /= (double)dag->points[i].samples;
    else
      dag->points[i].score = (double)dag->points[i].order;
  }
  dag_sort_points = dag->points;
  for (size_t layer = 0; layer < dag->layer_count; ++layer) {
    DagLayer *row = &dag->layers[layer];
    qsort(dag->layer_order + row->start, row->count, sizeof(size_t),
        compare_dag_points);
    for (size_t i = 0; i < row->count; ++i)
      dag->points[dag->layer_order[row->start + i]].order = i;
  }
}

/* Every graph edge advances in work_id, so a single ordered scan computes
   longest-path ranks. Private dummy points split long edges at each rank. */
static bool dag_layout_load(Ui *ui, DagLayout *dag) {
  memset(dag, 0, sizeof(*dag));
  size_t *next = NULL;
  static const char nodes_sql[] =
    "SELECT w.work_id,w.kind,CASE WHEN w.kind='model' AND EXISTS("
    "SELECT 1 FROM model_attempt a JOIN worker_session s USING(request_id) "
    "JOIN run_execution x ON x.execution_id=s.execution_id JOIN run_metadata r ON r.singleton=1 "
    "WHERE a.request_id=w.request_id AND s.execution_id=r.active_execution_id "
    "AND x.execution_id=r.active_execution_id AND r.status='running' AND x.ended_at_ns=0 "
    "AND s.state IN ('starting','working') AND a.state NOT IN ('sasCommitted','sasFailed') "
    "AND x.heartbeat_at_ns BETWEEN ?1-6000000000 AND ?1) THEN 'active' ELSE w.state END "
    "FROM work_occurrence w ORDER BY w.work_id";
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(ui->db, nodes_sql, -1, &stmt, NULL) != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "DAG read failed: %.420s", sqlite_error(ui->db));
    return false;
  }
  sqlite3_bind_int64(stmt, 1, ui->now_ns);
  int rc;
  while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
    if (!reserve_items((void **)&dag->nodes, &dag->node_capacity,
        dag->node_count + 1, sizeof(*dag->nodes))) {
      snprintf(ui->status, sizeof(ui->status), "DAG too large to lay out");
      sqlite3_finalize(stmt);
      dag_layout_free(dag);
      return false;
    }
    DagNode *node = &dag->nodes[dag->node_count++];
    memset(node, 0, sizeof(*node));
    node->id = sqlite3_column_int64(stmt, 0);
    node->glyph = work_glyph((const char *)sqlite3_column_text(stmt, 1));
    const char *state = (const char *)sqlite3_column_text(stmt, 2);
    snprintf(node->state, sizeof(node->state), "%s", state ? state : "?");
    if (node->id <= 0 || (dag->node_count > 1 &&
        dag->nodes[dag->node_count - 2].id >= node->id)) {
      snprintf(ui->status, sizeof(ui->status), "invalid DAG: work IDs are not strictly ordered");
      sqlite3_finalize(stmt);
      dag_layout_free(dag);
      return false;
    }
  }
  sqlite3_finalize(stmt);
  if (rc != SQLITE_DONE) {
    snprintf(ui->status, sizeof(ui->status), "DAG read failed: %.420s", sqlite_error(ui->db));
    dag_layout_free(dag);
    return false;
  }
  if (!dag->node_count) {
    dag->world_width = 5;
    dag->world_height = 3;
    return true;
  }

  if (sqlite3_prepare_v2(ui->db,
      "SELECT source_work_id,target_work_id FROM work_edge "
      "ORDER BY source_work_id,target_work_id,relation,position",
      -1, &stmt, NULL) != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "DAG edge read failed: %.410s", sqlite_error(ui->db));
    dag_layout_free(dag);
    return false;
  }
  while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
    int64_t source_id = sqlite3_column_int64(stmt, 0);
    int64_t target_id = sqlite3_column_int64(stmt, 1);
    size_t source = dag_node_index(dag, source_id);
    size_t target = dag_node_index(dag, target_id);
    if (source == SIZE_MAX || target == SIZE_MAX || source_id >= target_id) {
      snprintf(ui->status, sizeof(ui->status),
          "invalid DAG edge: #%" PRId64 " -> #%" PRId64, source_id, target_id);
      sqlite3_finalize(stmt);
      dag_layout_free(dag);
      return false;
    }
    if (!reserve_items((void **)&dag->edges, &dag->edge_capacity,
        dag->edge_count + 1, sizeof(*dag->edges))) {
      snprintf(ui->status, sizeof(ui->status), "DAG too large to lay out");
      sqlite3_finalize(stmt);
      dag_layout_free(dag);
      return false;
    }
    dag->edges[dag->edge_count++] = (DagEdge){.source = source, .target = target};
    size_t next_rank = dag->nodes[source].rank + 1;
    if (dag->nodes[target].rank < next_rank) dag->nodes[target].rank = next_rank;
  }
  sqlite3_finalize(stmt);
  if (rc != SQLITE_DONE) {
    snprintf(ui->status, sizeof(ui->status), "DAG edge read failed: %.410s", sqlite_error(ui->db));
    dag_layout_free(dag);
    return false;
  }

  size_t max_rank = 0, dummy_count = 0, segment_count = 0, path_count = 0;
  for (size_t i = 0; i < dag->node_count; ++i)
    if (max_rank < dag->nodes[i].rank) max_rank = dag->nodes[i].rank;
  if (max_rank == SIZE_MAX) {
    snprintf(ui->status, sizeof(ui->status), "DAG has too many layers");
    dag_layout_free(dag);
    return false;
  }
  dag->layer_count = max_rank + 1;
  dag->layers = calloc(dag->layer_count, sizeof(*dag->layers));
  if (!dag->layers) goto allocation_error;
  for (size_t i = 0; i < dag->node_count; ++i)
    dag->layers[dag->nodes[i].rank].count++;
  for (size_t i = 0; i < dag->edge_count; ++i) {
    DagEdge *edge = &dag->edges[i];
    size_t gap = dag->nodes[edge->target].rank - dag->nodes[edge->source].rank;
    if (!gap || gap == SIZE_MAX || dummy_count > SIZE_MAX - (gap - 1) ||
        segment_count > SIZE_MAX - gap || path_count > SIZE_MAX - (gap + 1))
      goto allocation_error;
    dummy_count += gap - 1;
    segment_count += gap;
    path_count += gap + 1;
    for (size_t rank = dag->nodes[edge->source].rank + 1;
        rank < dag->nodes[edge->target].rank; ++rank)
      dag->layers[rank].count++;
  }
  if (dag->node_count > SIZE_MAX - dummy_count) goto allocation_error;
  dag->point_count = dag->node_count + dummy_count;
  dag->segment_count = segment_count;
  dag->path_count = path_count;
  dag->points = calloc(dag->point_count, sizeof(*dag->points));
  dag->segments = segment_count ? calloc(segment_count, sizeof(*dag->segments)) : NULL;
  dag->paths = path_count && path_count <= SIZE_MAX / sizeof(*dag->paths) ?
      malloc(path_count * sizeof(*dag->paths)) : NULL;
  if (dag->point_count > SIZE_MAX / sizeof(*dag->layer_order))
    goto allocation_error;
  dag->layer_order = malloc(dag->point_count * sizeof(*dag->layer_order));
  if (!dag->points || (segment_count && !dag->segments) ||
      (path_count && !dag->paths) || !dag->layer_order) goto allocation_error;
  size_t offset = 0;
  for (size_t rank = 0; rank < dag->layer_count; ++rank) {
    dag->layers[rank].start = offset;
    offset += dag->layers[rank].count;
  }
  if (dag->layer_count > SIZE_MAX / sizeof(*next)) goto allocation_error;
  next = malloc(dag->layer_count * sizeof(*next));
  if (!next) goto allocation_error;
  for (size_t rank = 0; rank < dag->layer_count; ++rank)
    next[rank] = dag->layers[rank].start;
  for (size_t i = 0; i < dag->node_count; ++i) {
    DagNode *node = &dag->nodes[i];
    size_t point = i;
    node->point = point;
    dag->points[point] = (DagPoint){.node = i, .layer = node->rank,
      .stable = point, .is_node = true};
    dag->layer_order[next[node->rank]++] = point;
  }
  size_t point = dag->node_count, path_offset = 0, segment_offset = 0;
  for (size_t i = 0; i < dag->edge_count; ++i) {
    DagEdge *edge = &dag->edges[i];
    size_t source_rank = dag->nodes[edge->source].rank;
    size_t target_rank = dag->nodes[edge->target].rank;
    edge->path_start = path_offset;
    edge->path_count = target_rank - source_rank + 1;
    dag->paths[path_offset++] = dag->nodes[edge->source].point;
    for (size_t rank = source_rank + 1; rank < target_rank; ++rank) {
      size_t dummy = point++;
      dag->points[dummy] = (DagPoint){.node = SIZE_MAX, .layer = rank,
        .stable = dummy, .is_node = false};
      dag->layer_order[next[rank]++] = dummy;
      dag->paths[path_offset++] = dummy;
    }
    dag->paths[path_offset++] = dag->nodes[edge->target].point;
    for (size_t j = 1; j < edge->path_count; ++j) {
      dag->segments[segment_offset++] = (DagSegment){
        .source = dag->paths[edge->path_start + j - 1],
        .target = dag->paths[edge->path_start + j], .edge = i};
    }
  }
  free(next);
  next = NULL;
  for (size_t rank = 0; rank < dag->layer_count; ++rank)
    for (size_t i = 0; i < dag->layers[rank].count; ++i)
      dag->points[dag->layer_order[dag->layers[rank].start + i]].order = i;
  for (int sweep = 0; sweep < 3; ++sweep) {
    dag_barycenter_pass(dag, true);
    dag_barycenter_pass(dag, false);
  }
  size_t max_width = 0;
  for (size_t rank = 0; rank < dag->layer_count; ++rank)
    if (max_width < dag->layers[rank].count) max_width = dag->layers[rank].count;
  if (max_width > (size_t)((INT64_MAX - 5) / DAG_SLOT_STEP) ||
      dag->layer_count > (size_t)((INT64_MAX - 3) / DAG_LAYER_STEP))
    goto allocation_error;
  dag->world_width = (int64_t)(max_width - 1) * DAG_SLOT_STEP + 5;
  dag->world_height = (int64_t)(dag->layer_count - 1) * DAG_LAYER_STEP + 3;
  for (size_t rank = 0; rank < dag->layer_count; ++rank) {
    DagLayer *row = &dag->layers[rank];
    for (size_t i = 0; i < row->count; ++i) {
      size_t index = dag->layer_order[row->start + i];
      DagPoint *p = &dag->points[index];
      p->order = i;
      p->x = 2 + (int64_t)(max_width - row->count) * 2 + (int64_t)i * DAG_SLOT_STEP;
      p->y = 1 + (int64_t)rank * DAG_LAYER_STEP;
      if (p->is_node) {
        dag->nodes[p->node].rank = rank;
      }
    }
  }
  return true;

allocation_error:
  free(next);
  snprintf(ui->status, sizeof(ui->status), "DAG layout allocation or size limit exceeded");
  dag_layout_free(dag);
  return false;
}

enum { DAG_VERTICAL = 1, DAG_DIAG_LEFT = 2, DAG_DIAG_RIGHT = 4, DAG_HORIZONTAL = 8 };

static bool dag_edges_share_endpoint(const DagLayout *dag,
    size_t first, size_t second) {
  const DagEdge *a = &dag->edges[first], *b = &dag->edges[second];
  return a->source == b->source || a->target == b->target;
}

static void dag_paint(DagCell *cells, int width, int height,
    int64_t pan_x, int64_t pan_y, int64_t x, int64_t y,
    unsigned char glyph, unsigned char direction, size_t owner, bool highlight,
    const DagLayout *dag) {
  int64_t col = x - pan_x, row = y - pan_y;
  if (col < 0 || row < 0 || col >= width || row >= height) return;
  DagCell *cell = &cells[(size_t)row * (size_t)width + (size_t)col];
  cell->highlighted = cell->highlighted || highlight;
  if (!cell->occupied) {
    cell->occupied = true;
    cell->glyph = glyph;
    cell->directions = direction;
    cell->owner = owner;
  } else if (cell->owner == owner) {
    cell->directions |= direction;
    if ((cell->directions & (cell->directions - 1)) != 0 && cell->glyph != 'X')
      cell->glyph = cell->shared && !cell->branch ? 'X' : '+';
  } else {
    if (cell->glyph == 'X') return;
    cell->shared = true;
    if (cell->directions == direction) {
      cell->glyph = ':';
    } else if (dag_edges_share_endpoint(dag, cell->owner, owner)) {
      cell->glyph = '+';
      cell->branch = true;
    } else {
      cell->glyph = 'X';
    }
    cell->directions |= direction;
  }
}

static void dag_draw_segment(DagCell *cells, int width, int height,
    int64_t pan_x, int64_t pan_y, const DagPoint *source,
    const DagPoint *target, size_t owner, bool highlight,
    const DagLayout *dag) {
  int64_t sx = source->x, sy = source->y + (source->is_node ? 1 : 0);
  int64_t tx = target->x, ty = target->y - (target->is_node ? 1 : 0);
  int64_t dx = tx - sx, dy = ty - sy;
  if (dy <= 0) return;
  int sign = dx < 0 ? -1 : 1;
  uint64_t abs_dx = (uint64_t)(dx < 0 ? -dx : dx);
  uint64_t diagonal = abs_dx < (uint64_t)dy ? abs_dx : (uint64_t)dy;
  uint64_t horizontal = abs_dx - diagonal;
  uint64_t vertical = (uint64_t)dy - diagonal;
  if (horizontal) {
    int64_t end = sx + sign * (int64_t)horizontal;
    int64_t lo = sx < end ? sx : end, hi = sx > end ? sx : end;
    int64_t visible_lo = pan_x > lo ? pan_x : lo;
    int64_t viewport_hi = pan_x > INT64_MAX - (width - 1) ? INT64_MAX : pan_x + width - 1;
    int64_t visible_hi = viewport_hi < hi ? viewport_hi : hi;
    for (int64_t x = visible_lo; x <= visible_hi; ++x)
      dag_paint(cells, width, height, pan_x, pan_y, x, sy, '_',
          DAG_HORIZONTAL, owner, highlight, dag);
    sx = end;
  }
  if (vertical) {
    for (uint64_t i = 0; i <= vertical; ++i)
      dag_paint(cells, width, height, pan_x, pan_y, sx, sy + (int64_t)i,
          '|', DAG_VERTICAL, owner, highlight, dag);
    sy += (int64_t)vertical;
  }
  unsigned char glyph = sign < 0 ? '/' : '\\';
  unsigned char direction = sign < 0 ? DAG_DIAG_LEFT : DAG_DIAG_RIGHT;
  for (uint64_t i = 1; i <= diagonal; ++i)
    dag_paint(cells, width, height, pan_x, pan_y,
        sx + sign * (int64_t)i, sy + (int64_t)i,
        glyph, direction, owner, highlight, dag);
}

static void dag_pan(View *view, int64_t dx, int64_t dy) {
  if ((dx < 0 && view->graph_pan_x < -dx) ||
      (dx > 0 && view->graph_pan_x > INT64_MAX - dx))
    view->graph_pan_x = dx < 0 ? 0 : INT64_MAX;
  else
    view->graph_pan_x += dx;
  if ((dy < 0 && view->graph_pan_y < -dy) ||
      (dy > 0 && view->graph_pan_y > INT64_MAX - dy))
    view->graph_pan_y = dy < 0 ? 0 : INT64_MAX;
  else
    view->graph_pan_y += dy;
  if (view->graph_pan_x < 0) view->graph_pan_x = 0;
  if (view->graph_pan_y < 0) view->graph_pan_y = 0;
  view->graph_reveal_selection = false;
}

static bool dag_selected_id(const Item *item, int64_t *id) {
  if (!item || strcmp(item->table, "work_occurrence") != 0) return false;
  char *end = NULL;
  int64_t value = strtoll(item->key, &end, 10);
  if (!end || *end || value <= 0) return false;
  *id = value;
  return true;
}

static bool dag_snapshot_end(Ui *ui, bool owned, bool commit) {
  if (!owned) return true;
  int rc = sqlite3_exec(ui->db, commit ? "COMMIT" : "ROLLBACK", NULL, NULL, NULL);
  if (rc == SQLITE_OK) return true;
  snprintf(ui->status, sizeof(ui->status), "DAG snapshot failed: %.430s", sqlite_error(ui->db));
  sqlite3_exec(ui->db, "ROLLBACK", NULL, NULL, NULL);
  return false;
}

static bool graph_move_spatial(Ui *ui, int dx, int dy) {
  View *view = &ui->views[0];
  Item focus = selected_item(ui, view);
  int64_t focused_id;
  if (!dag_selected_id(&focus, &focused_id)) {
    snprintf(ui->status, sizeof(ui->status), "no selected work occurrence");
    return false;
  }
  bool owns_snapshot = sqlite3_get_autocommit(ui->db) != 0;
  if (owns_snapshot && sqlite3_exec(ui->db, "BEGIN", NULL, NULL, NULL) != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "DAG snapshot failed: %.430s", sqlite_error(ui->db));
    return false;
  }
  DagLayout dag;
  if (!dag_layout_load(ui, &dag)) {
    (void)dag_snapshot_end(ui, owns_snapshot, false);
    return false;
  }
  size_t selected = dag_node_index(&dag, focused_id);
  if (selected == SIZE_MAX) {
    dag_layout_free(&dag);
    if (!dag_snapshot_end(ui, owns_snapshot, true)) return false;
    snprintf(ui->status, sizeof(ui->status),
        "work #%" PRId64 " is absent from the current DAG", focused_id);
    return false;
  }
  DagPoint *origin = &dag.points[dag.nodes[selected].point];
  size_t best = SIZE_MAX;
  int64_t best_forward = INT64_MAX, best_lateral = INT64_MAX;
  for (size_t i = 0; i < dag.node_count; ++i) {
    if (i == selected) continue;
    DagPoint *candidate = &dag.points[dag.nodes[i].point];
    int64_t forward, lateral;
    if (dx != 0) {
      if (candidate->layer != origin->layer ||
          (dx < 0 ? candidate->x >= origin->x : candidate->x <= origin->x)) continue;
      forward = llabs(candidate->x - origin->x);
      lateral = llabs(candidate->y - origin->y);
    } else {
      if (dy < 0 ? candidate->y >= origin->y : candidate->y <= origin->y) continue;
      forward = llabs(candidate->y - origin->y);
      lateral = llabs(candidate->x - origin->x);
    }
    if (forward < best_forward ||
        (forward == best_forward && lateral < best_lateral) ||
        (forward == best_forward && lateral == best_lateral &&
            (best == SIZE_MAX || dag.nodes[i].id < dag.nodes[best].id))) {
      best = i;
      best_forward = forward;
      best_lateral = lateral;
    }
  }
  int64_t target_id = best == SIZE_MAX ? 0 : dag.nodes[best].id;
  dag_layout_free(&dag);
  if (!dag_snapshot_end(ui, owns_snapshot, true)) return false;
  if (best == SIZE_MAX) {
    const char *direction = dx < 0 ? "left in this rank" :
        dx > 0 ? "right in this rank" : dy < 0 ? "above" : "below";
    snprintf(ui->status, sizeof(ui->status), "no node %s", direction);
    return false;
  }
  return focus_work_id(ui, target_id);
}

static uintattr_t dag_state_color(const char *state) {
  if (strcmp(state, "active") == 0 || strcmp(state, "running") == 0) return UI_GOLD;
  if (strcmp(state, "failed") == 0) return UI_FAILED;
  if (strcmp(state, "completed") == 0) return UI_GREEN;
  if (strcmp(state, "waiting") == 0) return UI_STALE;
  if (strcmp(state, "queued") == 0) return UI_IDLE;
  return UI_FG;
}

static void draw_work_dag_panel(Ui *ui, View *view, int x, int y,
    int width, int height) {
  int inner = width - 2;
  if (inner < 2 || height < 3) return;
  int canvas_width = inner, canvas_height = height - 3;
  fill_row(x + 1, y + 1, inner, UI_TEAL, UI_BG);
  draw_plain(x + 1, y + 1, inner, "WORK DAG | top-down", UI_TEAL, UI_BG);
  if (ui->schema_version == 7) {
    draw_plain(x + 2, y + 2, inner - 2,
        "No DAG captured (schema 7)", UI_GOLD, UI_BG);
    return;
  }
  DagLayout dag;
  if (!dag_layout_load(ui, &dag)) {
    draw_plain(x + 2, y + 2, inner - 2,
        ui->status[0] ? ui->status : "DAG layout failed", UI_FAILED, UI_BG);
    return;
  }
  if (!dag.node_count) {
    draw_plain(x + 2, y + 2, inner - 2, "No work has been scheduled", UI_GOLD, UI_BG);
    dag_layout_free(&dag);
    return;
  }
  if (inner < 14 || canvas_height < 5) {
    draw_plain(x + 2, y + 2, inner - 2,
        "Resize for DAG overview; node navigation still works", UI_GOLD, UI_BG);
    dag_layout_free(&dag);
    return;
  }
  char selected_key[32] = "-";
  int64_t selected_id = 0;
  Item focused_item = selected_item(ui, view);
  bool has_selected = dag_selected_id(&focused_item, &selected_id);
  size_t selected_node = has_selected ? dag_node_index(&dag, selected_id) : SIZE_MAX;
  if (selected_node != SIZE_MAX) {
    snprintf(selected_key, sizeof(selected_key), "%" PRId64, selected_id);
    dag.nodes[selected_node].selected = true;
    for (size_t i = 0; i < dag.edge_count; ++i) {
      DagEdge *edge = &dag.edges[i];
      if (edge->source == selected_node) dag.nodes[edge->target].neighbor = true;
      if (edge->target == selected_node) dag.nodes[edge->source].neighbor = true;
    }
  }
  char title[160];
  snprintf(title, sizeof(title), "V=%zu E=%zu focus #%s",
      dag.node_count, dag.edge_count, selected_key);
  fill_row(x + 1, y + 1, inner, UI_TEAL, UI_BG);
  draw_plain(x + 1, y + 1, inner, title, UI_TEAL, UI_BG);
  if (canvas_width > 0 && canvas_height > 0 &&
      (size_t)canvas_width <= SIZE_MAX / (size_t)canvas_height &&
      (size_t)canvas_width * (size_t)canvas_height <= SIZE_MAX / sizeof(DagCell)) {
    DagCell *cells = calloc((size_t)canvas_width * (size_t)canvas_height,
        sizeof(*cells));
    if (!cells) {
      draw_plain(x + 2, y + 2, inner - 2, "DAG canvas allocation failed", UI_FAILED, UI_BG);
      dag_layout_free(&dag);
      return;
    }
    int64_t max_pan_x = dag.world_width > canvas_width ? dag.world_width - canvas_width : 0;
    int64_t max_pan_y = dag.world_height > canvas_height ? dag.world_height - canvas_height : 0;
    if (view->graph_pan_x > max_pan_x) view->graph_pan_x = max_pan_x;
    if (view->graph_pan_y > max_pan_y) view->graph_pan_y = max_pan_y;
    if (view->graph_reveal_selection && selected_node != SIZE_MAX) {
      DagPoint *focus = &dag.points[dag.nodes[selected_node].point];
      if (focus->x < view->graph_pan_x) view->graph_pan_x = focus->x;
      else if (focus->x >= view->graph_pan_x &&
          focus->x - view->graph_pan_x >= canvas_width)
        view->graph_pan_x = focus->x - canvas_width + 1;
      if (focus->y < view->graph_pan_y) view->graph_pan_y = focus->y;
      else if (focus->y >= view->graph_pan_y &&
          focus->y - view->graph_pan_y >= canvas_height)
        view->graph_pan_y = focus->y - canvas_height + 1;
      if (view->graph_pan_x > max_pan_x) view->graph_pan_x = max_pan_x;
      if (view->graph_pan_y > max_pan_y) view->graph_pan_y = max_pan_y;
      view->graph_reveal_selection = false;
    }
    for (size_t i = 0; i < dag.segment_count; ++i) {
      DagSegment *segment = &dag.segments[i];
      DagEdge *edge = &dag.edges[segment->edge];
      bool highlight = selected_node != SIZE_MAX &&
          (edge->source == selected_node || edge->target == selected_node);
      dag_draw_segment(cells, canvas_width, canvas_height,
          view->graph_pan_x, view->graph_pan_y,
          &dag.points[segment->source], &dag.points[segment->target],
          segment->edge, highlight, &dag);
    }
    for (int row = 0; row < canvas_height; ++row)
      for (int col = 0; col < canvas_width; ++col) {
        DagCell *cell = &cells[(size_t)row * (size_t)canvas_width + (size_t)col];
        if (!cell->occupied) continue;
        uintattr_t fg = cell->highlighted ? UI_ACCENT :
            cell->shared ? UI_STALE : UI_IDLE;
        tb_set_cell(x + 1 + col, y + 2 + row, cell->glyph, fg, UI_BG);
      }
    /* Edge marks are painted first; real occurrence glyphs win at endpoints. */
    for (size_t i = 0; i < dag.node_count; ++i) {
      DagNode *node = &dag.nodes[i];
      DagPoint *point = &dag.points[node->point];
      int64_t col = point->x - view->graph_pan_x;
      int64_t row = point->y - view->graph_pan_y;
      if (col < 0 || row < 0 || col >= canvas_width || row >= canvas_height) continue;
      uintattr_t fg = dag_state_color(node->state);
      if (node->neighbor) fg |= TB_BOLD;
      uintattr_t bg = UI_BG;
      if (node->selected) { fg = UI_SELECTED_FG; bg = UI_SELECTED_BG; }
      tb_set_cell(x + 1 + (int)col, y + 2 + (int)row, node->glyph, fg, bg);
    }
    free(cells);
  } else draw_plain(x + 2, y + 2, inner - 2, "DAG canvas size overflow", UI_FAILED, UI_BG);
  dag_layout_free(&dag);
}

static void session_title(Ui *ui, const View *view, char *output, size_t size) {
  sqlite3_stmt *stmt = NULL;
  static const char sql[] =
    "SELECT s.request_id,s.generation,s.state,a.model,a.effort,a.state,a.input_artifact_id,a.output_artifact_id "
    "FROM worker_session s LEFT JOIN model_attempt a USING(request_id) WHERE s.session_id=?1";
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) {
    snprintf(output, size, "LLM CONVERSATION | session=%s", view->parent.key);
    return;
  }
  sqlite3_bind_int64(stmt, 1, strtoll(view->parent.key, NULL, 10));
  if (sqlite3_step(stmt) == SQLITE_ROW) {
    char input[32] = "-", output_id[32] = "-";
    if (sqlite3_column_type(stmt, 6) != SQLITE_NULL)
      snprintf(input, sizeof(input), "#%" PRId64, sqlite3_column_int64(stmt, 6));
    if (sqlite3_column_type(stmt, 7) != SQLITE_NULL)
      snprintf(output_id, sizeof(output_id), "#%" PRId64, sqlite3_column_int64(stmt, 7));
    snprintf(output, size, "CHAT req=%.22s g=%d session=%s worker=%s/%s model=%.18s effort=%.8s I=%s O=%s",
        sqlite3_column_text(stmt, 0) ? (const char *)sqlite3_column_text(stmt, 0) : "?",
        sqlite3_column_int(stmt, 1), view->parent.key,
        sqlite3_column_text(stmt, 2) ? (const char *)sqlite3_column_text(stmt, 2) : "?",
        sqlite3_column_text(stmt, 5) ? (const char *)sqlite3_column_text(stmt, 5) : "?",
        sqlite3_column_text(stmt, 3) ? (const char *)sqlite3_column_text(stmt, 3) : "?",
        sqlite3_column_text(stmt, 4) ? (const char *)sqlite3_column_text(stmt, 4) : "?",
        input, output_id);
  } else snprintf(output, size, "LLM CONVERSATION | session=%s (missing)", view->parent.key);
  sqlite3_finalize(stmt);
}

static bool json_array_at(const char *s, JsonSpan array, int wanted, JsonSpan *out) {
  JsonCursor c = {s, strlen(s), array.a};
  json_ws(&c);
  if (c.p >= array.b || c.s[c.p++] != '[') return false;
  for (int i = 0;; ++i) {
    json_ws(&c);
    if (c.p >= array.b || c.s[c.p] == ']') return false;
    size_t start = c.p;
    if (!json_value_end(&c, 0)) return false;
    if (i == wanted) { out->a = start; out->b = c.p; return true; }
    json_ws(&c);
    if (c.p >= array.b || c.s[c.p++] != ',') return false;
  }
}

static void span_text(const char *s, JsonSpan span, char *out, size_t cap) {
  if (!cap) return;
  if (s[span.a] == '"' && json_string_copy(s, span, out, cap)) return;
  size_t n = span.b - span.a;
  if (n >= cap) n = cap - 1;
  memcpy(out, s + span.a, n); out[n] = '\0';
}

static void append_text(char **text, size_t *length, size_t *capacity,
    const char *value) {
  size_t n = strlen(value);
  if (n > SIZE_MAX - *length - 1) return;
  size_t needed = *length + n + 1;
  if (needed > *capacity) {
    size_t cap = *capacity ? *capacity : 128;
    while (cap < needed && cap <= SIZE_MAX / 2) cap *= 2;
    if (cap < needed) return;
    char *grown = realloc(*text, cap);
    if (!grown) return;
    *text = grown; *capacity = cap;
  }
  memcpy(*text + *length, value, n + 1); *length += n;
}

static void append_event_id(TranscriptCard *card, int64_t id) {
  for (size_t i = 0; i < card->event_count; ++i) if (card->events[i] == id) return;
  if (card->event_count == card->event_cap) {
    size_t cap = card->event_cap ? card->event_cap * 2 : 8;
    int64_t *grown = realloc(card->events, cap * sizeof(*grown));
    if (!grown) return;
    card->events = grown; card->event_cap = cap;
  }
  card->events[card->event_count++] = id;
  if (!card->primary_event) card->primary_event = id;
}

static TranscriptCard *chat_card(Ui *ui, const char *kind, const char *key,
    const char *label, int64_t timestamp) {
  for (int i = 0; i < ui->chat_count; ++i)
    if (strcmp(ui->chat[i].key, key) == 0) return &ui->chat[i];
  TranscriptCard *grown = realloc(ui->chat, (size_t)(ui->chat_count + 1) * sizeof(*grown));
  if (!grown) return NULL;
  ui->chat = grown;
  TranscriptCard *card = &ui->chat[ui->chat_count++];
  memset(card, 0, sizeof(*card));
  snprintf(card->kind, sizeof(card->kind), "%s", kind);
  snprintf(card->key, sizeof(card->key), "%s", key);
  if (ui->chat_assoc[0] && strcmp(ui->chat_assoc, "S") != 0)
    snprintf(card->label, sizeof(card->label), "[%s] %.72s", ui->chat_assoc, label);
  else snprintf(card->label, sizeof(card->label), "%s", label);
  card->exact_session = strcmp(ui->chat_assoc, "S") == 0;
  card->timestamp = timestamp;
  return card;
}

static void chat_remove_fallback(Ui *ui, const char *turn) {
  char key[320]; snprintf(key, sizeof(key), "user-fallback|%s", turn);
  for (int i = 0; i < ui->chat_count; ++i) if (strcmp(ui->chat[i].key, key) == 0 ||
      strcmp(ui->chat[i].key, "user-fallback|unknown") == 0) {
    free(ui->chat[i].text); free(ui->chat[i].events);
    memmove(&ui->chat[i], &ui->chat[i+1], (size_t)(ui->chat_count-i-1) * sizeof(*ui->chat));
    ui->chat_count--; return;
  }
}

static void item_text(const char *raw, JsonSpan item, char *out, size_t cap) {
  JsonSpan span, content, part;
  if (json_get(raw, item, "text", &span) && json_string_copy(raw, span, out, cap)) return;
  out[0] = '\0';
  if (!json_get(raw, item, "content", &content)) return;
  for (int i = 0; json_array_at(raw, content, i, &part); ++i) {
    char chunk[2048] = "";
    if (json_get(raw, part, "text", &span)) json_string_copy(raw, span, chunk, sizeof(chunk));
    if (chunk[0] && strlen(out) + strlen(chunk) + 2 < cap) {
      if (out[0]) strncat(out, "\n", cap - strlen(out) - 1);
      strncat(out, chunk, cap - strlen(out) - 1);
    }
  }
}

static void chat_json_body(const char *raw, JsonSpan value, char *out, size_t cap) {
  size_t n = value.b - value.a;
  char *copy = malloc(n + 1);
  if (!copy) { snprintf(out, cap, "[event value too large]"); return; }
  memcpy(copy, raw + value.a, n); copy[n] = '\0';
  char *pretty = pretty_json(copy);
  snprintf(out, cap, "%s", pretty ? pretty : copy);
  free(pretty); free(copy);
}

static void load_transcript(Ui *ui, View *view) {
  Item previous = {0};
  bool first_load = !view->transcript_initialized;
  view->transcript_initialized = true;
  bool had_previous = view->selected >= 0 && view->selected < ui->page_count;
  if (had_previous) previous = ui->page[view->selected];
  if (first_load) view->detail_scroll = -1;
  for (int i = 0; i < ui->chat_count; ++i) {
    free(ui->chat[i].text); free(ui->chat[i].events);
  }
  free(ui->chat); ui->chat = NULL; ui->chat_count = 0;
  static const char sql[] =
    "WITH s AS (SELECT * FROM worker_session WHERE session_id=CAST(?1 AS INTEGER)) "
    "SELECT e.event_id,e.direction,e.rpc_id,e.raw_json,e.timestamp_ns,e.execution_id,e.request_id,e.session_id,e.thread_id,e.turn_id, "
    "CASE WHEN e.session_id=s.session_id AND (e.execution_id<>s.execution_id OR (e.request_id<>'' AND e.request_id<>s.request_id)) THEN '!' "
    "WHEN e.session_id=s.session_id THEN 'S' WHEN e.session_id IS NULL AND e.request_id=s.request_id THEN 'R?' ELSE 'T?' END "
    "FROM conversation_event e,s WHERE e.session_id=s.session_id OR "
    "(e.session_id IS NULL AND e.request_id=s.request_id AND e.execution_id=s.execution_id "
    "AND (SELECT COUNT(*) FROM worker_session x WHERE x.request_id=s.request_id)=1) OR "
    "(e.session_id IS NULL AND s.thread_id<>'' AND e.thread_id=s.thread_id AND e.execution_id=s.execution_id "
    "AND (e.request_id='' OR e.request_id=s.request_id) AND "
    "(SELECT COUNT(*) FROM worker_session x WHERE x.execution_id=s.execution_id AND x.thread_id=s.thread_id)=1) "
    "ORDER BY e.timestamp_ns,e.event_id";
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(ui->db, sql, -1, &stmt, NULL) != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "chat read failed: %.400s", sqlite_error(ui->db));
    ui->page_count = 0; return;
  }
  sqlite3_bind_int64(stmt, 1, strtoll(view->parent.key, NULL, 10));
  int rc;
  while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
    int64_t id = sqlite3_column_int64(stmt, 0), ts = sqlite3_column_int64(stmt, 4);
    const char *direction = (const char *)sqlite3_column_text(stmt, 1);
    const char *rpc = (const char *)sqlite3_column_text(stmt, 2);
    const char *raw = (const char *)sqlite3_column_text(stmt, 3);
    const char *association = (const char *)sqlite3_column_text(stmt, 10);
    snprintf(ui->chat_assoc, sizeof(ui->chat_assoc), "%s", association ? association : "?");
    if (!raw || !raw[0]) continue;
    if (association && strcmp(association, "!") == 0) {
      char key[64], label[96], body[256];
      snprintf(key, sizeof(key), "conflict|%" PRId64, id);
      snprintf(label, sizeof(label), "Conflicting association");
      snprintf(body, sizeof(body), "Event #%" PRId64 " is linked to this session but its request or execution conflicts.", id);
      TranscriptCard *card = chat_card(ui, "Unparsed", key, label, ts);
      if (card) { append_event_id(card, id); append_text(&card->text, &card->text_len, &card->text_cap, body); }
      continue;
    }
    JsonSpan root = {0, strlen(raw)}, params = {0}, item = {0}, span = {0};
    char method[96] = "", item_type[64] = "", item_id[256] = "", turn[256] = "";
    bool valid = json_member(raw, root, "method", method, sizeof(method));
    if (!valid) {
      char *formatted = pretty_json(raw);
      if (formatted) { free(formatted); continue; } /* ordinary JSON-RPC response */
      char key[64]; snprintf(key, sizeof(key), "bad-json|%" PRId64, id);
      TranscriptCard *card = chat_card(ui, "Unparsed", key, "Unparsed event", ts);
      if (card) { append_event_id(card, id); append_text(&card->text, &card->text_len, &card->text_cap, "Malformed JSON; Enter opens its stored event."); }
      continue;
    }
    (void)json_get(raw, root, "params", &params);
    (void)json_member(raw, params, "turnId", turn, sizeof(turn));
    if (json_get(raw, params, "item", &item)) {
      (void)json_member(raw, item, "type", item_type, sizeof(item_type));
      (void)json_member(raw, item, "id", item_id, sizeof(item_id));
    }
    if (strcmp(method, "thread/start") == 0) {
      char context[4096] = "";
      if (json_member(raw, params, "developerInstructions", context, sizeof(context))) {
        TranscriptCard *card = chat_card(ui, "Context", "context/developer", "Developer instructions", ts);
        if (card) { append_event_id(card, id); append_text(&card->text, &card->text_len, &card->text_cap, context); }
      }
    } else if (strcmp(method, "thread/goal/set") == 0) {
      char context[2048] = "";
      if (json_member(raw, params, "objective", context, sizeof(context))) {
        TranscriptCard *card = chat_card(ui, "Context", "context/goal", "Thread goal", ts);
        if (card) { append_event_id(card, id); append_text(&card->text, &card->text_len, &card->text_cap, context); }
      }
    } else if (strcmp(method, "turn/start") == 0) {
      JsonSpan input;
      if (json_get(raw, params, "input", &input)) {
        char key[320]; snprintf(key, sizeof(key), "user-fallback|%s", turn[0] ? turn : "unknown");
        TranscriptCard *card = chat_card(ui, "User", key, "User input (fallback)", ts);
        if (card) {
          append_event_id(card, id);
          for (int i = 0; json_array_at(raw, input, i, &span); ++i) {
            char text[2048] = "";
            if (json_get(raw, span, "text", &item)) json_string_copy(raw, item, text, sizeof(text));
            if (text[0]) { append_text(&card->text, &card->text_len, &card->text_cap, text); append_text(&card->text, &card->text_len, &card->text_cap, "\n"); }
          }
        }
      }
    } else if (strcmp(item_type, "userMessage") == 0 && item_id[0]) {
      chat_remove_fallback(ui, turn);
      char key[640]; snprintf(key, sizeof(key), "user|%s|%s", turn, item_id);
      TranscriptCard *card = chat_card(ui, "User", key, "User", ts);
      if (card) {
        append_event_id(card, id);
        char text[8192] = ""; item_text(raw, item, text, sizeof(text));
        if (text[0] && (!card->text || !card->text[0])) append_text(&card->text, &card->text_len, &card->text_cap, text);
      }
    } else if (strcmp(method, "item/agentMessage/delta") == 0) {
      char idtext[256] = "", delta[2048] = "";
      (void)json_member(raw, params, "itemId", idtext, sizeof(idtext));
      (void)json_member(raw, params, "delta", delta, sizeof(delta));
      if (!idtext[0]) continue;
      char key[640]; snprintf(key, sizeof(key), "agent|%s|%s", turn, idtext);
      TranscriptCard *card = chat_card(ui, "Agent", key, "Agent", ts);
      if (card) { append_event_id(card, id); append_text(&card->text, &card->text_len, &card->text_cap, delta); }
    } else if (strcmp(item_type, "agentMessage") == 0 && item_id[0]) {
      char key[640]; snprintf(key, sizeof(key), "agent|%s|%s", turn, item_id);
      TranscriptCard *card = chat_card(ui, "Agent", key, "Agent", ts);
      if (card) {
        append_event_id(card, id);
        if (strcmp(method, "item/completed") == 0) card->completed = true;
        char text[8192] = ""; item_text(raw, item, text, sizeof(text));
        if (text[0]) { free(card->text); card->text = NULL; card->text_len = card->text_cap = 0; append_text(&card->text, &card->text_len, &card->text_cap, text); }
      }
    } else if (strcmp(method, "item/tool/call") == 0 && strcmp(direction ? direction : "", "incoming") == 0) {
      char tool[128] = "tool", call_id[256] = ""; JsonSpan args;
      (void)json_member(raw, params, "tool", tool, sizeof(tool));
      (void)json_member(raw, params, "callId", call_id, sizeof(call_id));
      char key[256]; snprintf(key, sizeof(key), "rpc-call|%s|%" PRId64, rpc ? rpc : "", id);
      TranscriptCard *card = chat_card(ui, "Tool", key, tool, ts);
      if (card) {
        card->rpc_request = true;
        card->exact_session = association && strcmp(association, "S") == 0;
        snprintf(card->rpc_id, sizeof(card->rpc_id), "%s", rpc ? rpc : "");
        snprintf(card->call_id, sizeof(card->call_id), "%s", call_id);
        snprintf(card->turn_id, sizeof(card->turn_id), "%s", turn);
        append_event_id(card, id);
        if (json_get(raw, params, "arguments", &args)) {
          char args_text[4096]; chat_json_body(raw, args, args_text, sizeof(args_text));
          append_text(&card->text, &card->text_len, &card->text_cap, args_text);
        }
      }
    } else if (strcmp(item_type, "dynamicToolCall") == 0 || strcmp(item_type, "commandExecution") == 0) {
      if (!item_id[0]) continue;
      bool command = strcmp(item_type, "commandExecution") == 0;
      char key[640]; snprintf(key, sizeof(key), "%s|%s", command ? "command" : "dynamic-tool", item_id);
      TranscriptCard *card = chat_card(ui, command ? "Command" : "Tool", key,
          command ? "Command" : "Tool", ts);
      if (card) {
        card->lifecycle_tool = !command;
        card->exact_session = association && strcmp(association, "S") == 0;
        snprintf(card->call_id, sizeof(card->call_id), "%s", item_id);
        snprintf(card->turn_id, sizeof(card->turn_id), "%s", turn);
        append_event_id(card, id);
        JsonSpan text_span;
        if (json_get(raw, item, "command", &text_span)) { char value[1024]; span_text(raw, text_span, value, sizeof(value)); append_text(&card->text, &card->text_len, &card->text_cap, value); append_text(&card->text, &card->text_len, &card->text_cap, "\n"); }
        char output_text[4096] = ""; item_text(raw, item, output_text, sizeof(output_text));
        if (output_text[0]) append_text(&card->text, &card->text_len, &card->text_cap, output_text);
        else { char raw_item[2048]; chat_json_body(raw, item, raw_item, sizeof(raw_item)); append_text(&card->text, &card->text_len, &card->text_cap, raw_item); }
      }
    } else if (direction && strcmp(direction, "outgoing") == 0 && rpc && rpc[0] &&
        (json_get(raw, root, "result", &span) || json_get(raw, root, "error", &span))) {
      char key[256]; snprintf(key, sizeof(key), "rpc-result|%s|%" PRId64, rpc, id);
      TranscriptCard *card = chat_card(ui, "Tool result", key, "Tool result unpaired", ts);
      if (card) {
        card->rpc_result = true; snprintf(card->rpc_id, sizeof(card->rpc_id), "%s", rpc);
        card->exact_session = association && strcmp(association, "S") == 0;
        append_event_id(card, id); char result[4096]; chat_json_body(raw, span, result, sizeof(result));
        append_text(&card->text, &card->text_len, &card->text_cap, result);
      }
    } else if ((strcmp(method, "item/started") == 0 || strcmp(method, "item/completed") == 0) &&
        strcmp(item_type, "reasoning") == 0) {
      continue;
    } else if (strcmp(method, "turn/started") == 0 || strcmp(method, "turn/completed") == 0 ||
        strncmp(method, "thread/", 7) == 0 || strncmp(method, "account/", 8) == 0 ||
        strncmp(method, "mcpServer/", 10) == 0 || strncmp(method, "rateLimits/", 11) == 0 ||
        strncmp(method, "token/", 6) == 0 || strncmp(method, "status/", 7) == 0) {
      continue;
    } else {
      char key[64], raw_text[2048]; snprintf(key, sizeof(key), "unknown|%" PRId64, id);
      TranscriptCard *card = chat_card(ui, "Unparsed", key, "Unparsed event", ts);
      if (card) {
        append_event_id(card, id); chat_json_body(raw, root, raw_text, sizeof(raw_text));
        append_text(&card->text, &card->text_len, &card->text_cap, raw_text);
      }
    }
  }
  sqlite3_finalize(stmt);
  if (rc != SQLITE_DONE) snprintf(ui->status, sizeof(ui->status), "chat read failed: %.400s", sqlite_error(ui->db));
  for (int i = 0; i < ui->chat_count; ++i) if (ui->chat[i].lifecycle_tool && ui->chat[i].exact_session) {
    int match = -1, matches = 0;
    for (int j = 0; j < ui->chat_count; ++j) if (ui->chat[j].rpc_request &&
        ui->chat[j].exact_session && ui->chat[j].call_id[0] &&
        strcmp(ui->chat[i].call_id, ui->chat[j].call_id) == 0 &&
        (!ui->chat[i].turn_id[0] || !ui->chat[j].turn_id[0] ||
         strcmp(ui->chat[i].turn_id, ui->chat[j].turn_id) == 0)) { match = j; matches++; }
    if (matches == 1) {
      append_text(&ui->chat[match].text, &ui->chat[match].text_len, &ui->chat[match].text_cap, "\n\nTool lifecycle:\n");
      append_text(&ui->chat[match].text, &ui->chat[match].text_len, &ui->chat[match].text_cap,
          ui->chat[i].text ? ui->chat[i].text : "(empty)");
      for (size_t k = 0; k < ui->chat[i].event_count; ++k) append_event_id(&ui->chat[match], ui->chat[i].events[k]);
      ui->chat[i].hidden = true; ui->chat[match].paired_result = true;
    }
  }
  for (int i = 0; i < ui->chat_count; ++i) if (ui->chat[i].rpc_request && ui->chat[i].exact_session) {
    int calls = 0, results = 0, ri = -1;
    for (int j = 0; j < ui->chat_count; ++j) if (ui->chat[j].exact_session && strcmp(ui->chat[i].rpc_id, ui->chat[j].rpc_id) == 0) {
      calls += ui->chat[j].rpc_request; if (ui->chat[j].rpc_result) { results++; ri = j; }
    }
    if (calls == 1 && results == 1) {
      append_text(&ui->chat[i].text, &ui->chat[i].text_len, &ui->chat[i].text_cap, "\n\nResult:\n");
      append_text(&ui->chat[i].text, &ui->chat[i].text_len, &ui->chat[i].text_cap,
          ui->chat[ri].text ? ui->chat[ri].text : "(empty)");
      for (size_t k = 0; k < ui->chat[ri].event_count; ++k) append_event_id(&ui->chat[i], ui->chat[ri].events[k]);
      ui->chat[ri].hidden = true;
      ui->chat[i].paired_result = true;
    } else if (results == 1) {
      snprintf(ui->chat[ri].label, sizeof(ui->chat[ri].label), "Tool result unpaired");
    }
  }
  for (int i = 0; i < ui->chat_count; ++i) if (ui->chat[i].rpc_result) {
    if (!ui->chat[i].exact_session) {
      snprintf(ui->chat[i].label, sizeof(ui->chat[i].label), "Tool result unpaired");
      continue;
    }
    int calls = 0, results = 0;
    for (int j = 0; j < ui->chat_count; ++j) if (strcmp(ui->chat[i].rpc_id, ui->chat[j].rpc_id) == 0) {
      if (ui->chat[j].exact_session) { calls += ui->chat[j].rpc_request; results += ui->chat[j].rpc_result; }
    }
    if (calls != 1 || results != 1)
      snprintf(ui->chat[i].label, sizeof(ui->chat[i].label), "Tool result unpaired");
  }
  for (int i = 0; i < ui->chat_count; ++i) if (ui->chat[i].rpc_request && !ui->chat[i].paired_result)
    snprintf(ui->chat[i].label, sizeof(ui->chat[i].label), "Tool call unpaired");
  int visible = 0;
  for (int i = 0; i < ui->chat_count; ++i) if (!ui->chat[i].hidden) visible++;
  if (!had_previous && view->offset == 0 && visible > PAGE_SIZE)
    view->offset = ((visible - 1) / PAGE_SIZE) * PAGE_SIZE;
  if (view->offset >= visible) view->offset = visible > PAGE_SIZE ? ((visible - 1) / PAGE_SIZE) * PAGE_SIZE : 0;
  ui->page_count = 0;
  int position = 0;
  for (int i = 0; i < ui->chat_count && ui->page_count < PAGE_SIZE; ++i) {
    TranscriptCard *card = &ui->chat[i]; if (card->hidden) continue;
    if (position++ < view->offset) continue;
    Item *item = &ui->page[ui->page_count++];
    char key[64], label[MAX_LABEL];
    snprintf(key, sizeof(key), "%" PRId64, card->primary_event);
    snprintf(label, sizeof(label), "%s | #%" PRId64, card->label, card->primary_event);
    if (card->event_count > 1) {
      size_t used = strlen(label);
      snprintf(label + used, sizeof(label) - used, " +%zu", card->event_count - 1);
    }
    item_set(item, "conversation_event", "event_id", key, label);
  }
  if (ui->page_count) {
    int match = -1;
    if (had_previous) for (int i = 0; i < ui->page_count; ++i)
      if (strcmp(previous.key, ui->page[i].key) == 0) { match = i; break; }
    if (match >= 0) view->selected = match;
    else if (view->selected >= ui->page_count) view->selected = ui->page_count - 1;
    if (view->selected < 0 && first_load) view->selected = ui->page_count - 1;
  } else view->selected = -1;
}

static int transcript_layout(Ui *ui, int width, int *selected_start) {
  int line = 0;
  *selected_start = -1;
  for (int i = 0; i < ui->chat_count; ++i) {
    TranscriptCard *card = &ui->chat[i]; if (card->hidden) continue;
    int page_index = -1;
    for (int p = 0; p < ui->page_count; ++p)
      if (strtoll(ui->page[p].key, NULL, 10) == card->primary_event) { page_index = p; break; }
    if (page_index >= 0 && page_index == ui->views[ui->depth].selected) *selected_start = line;
    line++;
    const char *text = card->text && card->text[0] ? card->text : "(empty; Enter opens source event JSON)";
    draw_value(0, 0, width - 2, 0, text, 0, &line, UI_FG);
    line++;
  }
  return line;
}

static void reveal_chat_selection(Ui *ui, int width, int viewport_height) {
  View *view = &ui->views[ui->depth];
  int selected_start = -1;
  (void)transcript_layout(ui, width, &selected_start);
  if (selected_start < 0) return;
  if (viewport_height < 1) viewport_height = 1;
  if (selected_start < view->detail_scroll) view->detail_scroll = selected_start;
  else if (selected_start >= view->detail_scroll + viewport_height)
    view->detail_scroll = selected_start - viewport_height + 1;
}

static void draw_transcript(Ui *ui, int x, int y, int width, int height, int scroll) {
  int line = 0;
  for (int i = 0; i < ui->chat_count; ++i) {
    TranscriptCard *card = &ui->chat[i]; if (card->hidden) continue;
    int page_index = -1;
    for (int p = 0; p < ui->page_count; ++p)
      if (strtoll(ui->page[p].key, NULL, 10) == card->primary_event) { page_index = p; break; }
    char heading[512], sources[256] = "";
    for (size_t k = 0; k < card->event_count; ++k) {
      size_t used = strlen(sources);
      snprintf(sources + used, sizeof(sources) - used, "%s%" PRId64,
          k ? "," : "", card->events[k]);
    }
    snprintf(heading, sizeof(heading), "%s%s  [%s]",
        card->label, strcmp(card->kind, "Agent") == 0 && !card->completed ? " [in progress]" : "",
        sources[0] ? sources : "no source ID");
    if (line >= scroll && line - scroll < height) {
      uintattr_t fg = page_index == ui->views[ui->depth].selected ? UI_SELECTED_FG : UI_ACCENT;
      uintattr_t bg = page_index == ui->views[ui->depth].selected ? UI_SELECTED_BG : UI_BG;
      if (page_index == ui->views[ui->depth].selected) fill_row(x, y + line - scroll, width, fg, bg);
      draw_plain(x, y + line - scroll, width, heading, fg, bg);
    }
    line++;
    const char *text = card->text && card->text[0] ? card->text : "(empty; Enter opens source event JSON)";
    draw_value(x + 2, y, width - 2, height, text, scroll, &line, UI_FG);
    line++;
  }
  if (ui->chat_count == 0) draw_plain(x, y, width, "No readable chat messages were captured for this session.", UI_GOLD, UI_BG);
}

static bool render(Ui *ui) {
  View *view = &ui->views[ui->depth];
  ui->status[0] = '\0';
  if (tb_width() < 40 || tb_height() < 10) {
    tb_clear();
    draw_plain(0, 0, tb_width(), "Resize terminal to at least 40x10", UI_GOLD, UI_BG);
    tb_present();
    return true;
  }
  if (sqlite3_exec(ui->db, "BEGIN", NULL, NULL, NULL) != SQLITE_OK) {
    snprintf(ui->status, sizeof(ui->status), "refresh failed: %.440s", sqlite_error(ui->db));
    return false;
  }
  if (!read_header(ui)) {
    snprintf(ui->status, sizeof(ui->status), "snapshot read failed: %.420s", sqlite_error(ui->db));
    sqlite3_exec(ui->db, "ROLLBACK", NULL, NULL, NULL);
    return false;
  }
  if (view->kind == view_session) load_transcript(ui, view);
  else if (current_list_count(ui, view) < 0) {
    sqlite3_exec(ui->db, "ROLLBACK", NULL, NULL, NULL);
    return false;
  }
  Item item = selected_item(ui, view);
  int width = tb_width(), height = tb_height();
  int left_width = view->kind == view_graph ?
      (width >= 90 ? width * 56 / 100 : width * 55 / 100) :
      view->kind == view_session ? width - 1 :
      (width >= 70 ? width * 42 / 100 : width / 2);
  if (left_width < 18) left_width = 18;
  if (left_width > width - 18) left_width = width - 18;
  int top = 3, body_height = height - top - 2;
  if (body_height < 1) body_height = 1;
  if (view->kind == view_session) {
    int selected_start = -1;
    int total_lines = transcript_layout(ui, width - 4, &selected_start);
    int viewport = body_height - 4;
    if (viewport < 1) viewport = 1;
    int max_scroll = total_lines > viewport ? total_lines - viewport : 0;
    if (view->detail_scroll < 0 || view->reveal_selection) {
      if (view->detail_scroll < 0) view->detail_scroll = 0;
      reveal_chat_selection(ui, width - 4, viewport);
      view->reveal_selection = false;
    }
    if (view->detail_scroll > max_scroll) view->detail_scroll = max_scroll;
  }
  tb_clear();
  draw_plain(0, 0, width, ui->database_path, UI_ACCENT, UI_BG);
  draw_plain(0, 1, width, ui->header, UI_FG, UI_BG);
  char title[256];
  if (view->kind == view_session) {
    session_title(ui, view, title, sizeof(title));
    size_t used = strlen(title);
    snprintf(title + used, sizeof(title) - used, " | transcript");
  } else if (view->kind == view_graph)
    snprintf(title, sizeof(title), "%s | work #%s | pane=%s",
        context_title(view), item.table[0] ? item.key : "none",
        ui->details_focused ? "details" : "DAG");
  else snprintf(title, sizeof(title), "%s | focus: %s", context_title(view),
      ui->details_focused ? "details" : "list");
  draw_plain(0, 2, width, title, UI_TEAL, UI_BG);
  draw_box(0, top, left_width, body_height);
  draw_box(left_width, top, width-left_width, body_height);
  int list_inner_width = left_width - 2;
  if (view->kind == view_graph) {
    draw_work_dag_panel(ui, view, 0, top, left_width, body_height);
    draw_plain(left_width+1, top+1, width-left_width-2,
        "SELECTED WORK | edges are explicit", UI_TEAL, UI_BG);
    draw_work_dag_detail(ui, &item, left_width+2, top+2,
        width-left_width-3, body_height-3, view->detail_scroll);
  } else if (view->kind == view_session) {
    draw_plain(1, top + 1, width - 2,
        "Transcript | Enter=source JSON | [/] generation | d/u scroll", UI_TEAL, UI_BG);
    draw_transcript(ui, 2, top + 2, width - 4, body_height - 4, view->detail_scroll);
  } else {
    draw_plain(1, top+1, list_inner_width,
        view->parent.table[0] ? view->parent.key : "", UI_ACCENT, UI_BG);
    int visible_rows = body_height - 3;
    int list_start = view->selected >= visible_rows ? view->selected - visible_rows + 1 : 0;
    for (int i = 0; i < visible_rows && list_start + i < ui->page_count; ++i) {
      char line[MAX_LABEL + 4];
      int index = list_start + i;
      snprintf(line, sizeof(line), "%c %.950s", index == view->selected ? '>' : ' ', ui->page[index].label);
      bool selected = index == view->selected;
      uintattr_t fg = selected ? UI_SELECTED_FG : UI_FG;
      uintattr_t bg = selected ? UI_SELECTED_BG : UI_BG;
      if (selected) fill_row(1, top+2+i, list_inner_width, fg, bg);
      draw_plain(1, top+2+i, list_inner_width, line, fg, bg);
    }
    if (view->offset > 0)
      draw_plain(1, top+body_height-2, list_inner_width, "[older rows above]", UI_GOLD, UI_BG);
    if (ui->page_count == PAGE_SIZE)
      draw_plain(1, top+body_height-1, list_inner_width, "[more rows below]", UI_GOLD, UI_BG);
    draw_record(ui, &item, left_width+2, top+1, width-left_width-3,
        body_height-2, view->detail_scroll);
  }
  if (ui->help) {
    draw_plain(0, height-2, width,
        "hjkl spatial [incoming ]outgoing HJKL pan Tab detail i inspect c chat q",
        UI_TEAL, UI_BG);
    draw_plain(0, height-1, width,
        "M model R ref A raw I iter S SO F fan L lift J join | + branch : share X cross",
        UI_TEAL, UI_BG);
  } else if (ui->status[0]) {
    draw_plain(0, height-2, width, ui->status, UI_ACCENT, UI_ERROR_BG);
  } else {
    const char *hint;
    if (view->kind == view_graph)
      hint = ui->details_focused ?
          "DETAIL j/k scroll d/u page Tab DAG c chat ? help q quit" :
          "hjkl spatial [in ]out HJKL pan Tab detail c chat ?";
    else if (view->kind == view_session)
      hint = "CHAT j/k card d/u scroll Enter JSON I/O [/] gen h back g graph ? q";
    else
      hint = ui->details_focused ?
          "DETAIL j/k scroll d/u page Tab list h back g graph c chat ? help q quit" :
          "j/k select l open h back d/u scroll Tab detail g graph c chat ? help q quit";
    draw_plain(0, height-2, width, hint, UI_FG, UI_BG);
    const char *explanation = view->kind == view_session ?
        "r refresh | S=session R?=request/gen? T?=thread !=conflict; raw JSON." :
        view->kind == view_graph ?
        "M/R/A/I/S/F/L/J | + branch : share X cross | color=status" :
        "r refresh | ACTIVE=DB worker+unfinished attempt+heartbeat<6s; OS unverified.";
    draw_plain(0, height-1, width, explanation, UI_GOLD, UI_BG);
  }
  int rc = sqlite3_exec(ui->db, "COMMIT", NULL, NULL, NULL);
  if (rc != SQLITE_OK) {
    sqlite3_exec(ui->db, "ROLLBACK", NULL, NULL, NULL);
    snprintf(ui->status, sizeof(ui->status), "snapshot commit failed: %.420s", sqlite_error(ui->db));
  }
  tb_present();
  return rc == SQLITE_OK;
}

static void draw_refresh_error(Ui *ui) {
  int y = tb_height() - 2;
  if (y >= 0) {
    draw_plain(0, y, tb_width(), ui->status, UI_ACCENT, UI_ERROR_BG);
    tb_present();
  }
}

static void move_selection(Ui *ui, int direction) {
  View *view = &ui->views[ui->depth];
  if (ui->details_focused && ui->views[ui->depth].kind != view_session) {
    if (direction > 0) view->detail_scroll++;
    else if (view->detail_scroll > 0) view->detail_scroll--;
    return;
  }
  int previous = view->selected;
  if (direction > 0) {
    if (view->selected + 1 < ui->page_count) view->selected++;
    else if (ui->page_count == PAGE_SIZE) { view->offset += PAGE_SIZE; view->selected = 0; }
  } else {
    if (view->selected > 0) view->selected--;
    else if (view->offset > 0) { view->offset -= PAGE_SIZE; view->selected = PAGE_SIZE - 1; }
    else view->selected = -1;
  }
  if (view->selected != previous) {
    if (view->kind == view_graph) {
      view->graph_neighbor_ready = false;
      view->graph_neighbor_origin = 0;
      view->graph_neighbor_index = 0;
      view->graph_reveal_selection = true;
    }
    if (view->kind == view_session) view->reveal_selection = true;
    else view->detail_scroll = 0;
  }
}

static void scroll_detail(Ui *ui, int amount) {
  View *view = &ui->views[ui->depth];
  int scroll = view->detail_scroll + amount;
  if (view->kind == view_session) {
    int selected_start = -1;
    int total = transcript_layout(ui, tb_width() - 4, &selected_start);
    int viewport = tb_height() - 9;
    if (viewport < 1) viewport = 1;
    int max_scroll = total > viewport ? total - viewport : 0;
    if (scroll < 0) scroll = 0;
    if (scroll > max_scroll) scroll = max_scroll;
  } else if (scroll < 0) scroll = 0;
  view->detail_scroll = scroll;
}

static void switch_view(Ui *ui, ViewKind kind) {
  if (ui->views[ui->depth].kind == kind) {
    ui->views[ui->depth].offset = 0;
    ui->views[ui->depth].selected = 0;
    ui->views[ui->depth].detail_scroll = 0;
    return;
  }
  push_view(ui, kind, NULL);
  ui->views[ui->depth].selected = -1;
}

static void handle_key(Ui *ui, const struct tb_event *event, bool *quit) {
  View *view = &ui->views[ui->depth];
  if (view->kind == view_graph && !ui->details_focused &&
      (event->ch == 'H' || event->ch == 'J' || event->ch == 'K' || event->ch == 'L')) {
    int term_width = tb_width();
    int left_width = term_width >= 90 ? term_width * 56 / 100 : term_width * 55 / 100;
    int horizontal_step = left_width > 6 ? left_width - 6 : 1;
    int vertical_step = tb_height() > 8 ? tb_height() - 8 : 1;
    dag_pan(view,
        event->ch == 'H' ? -horizontal_step : event->ch == 'L' ? horizontal_step : 0,
        event->ch == 'K' ? -vertical_step : event->ch == 'J' ? vertical_step : 0);
  } else if (view->kind == view_graph && !ui->details_focused &&
      (event->key == TB_KEY_ARROW_LEFT || event->ch == 'h')) {
    view->graph_neighbor_ready = false;
    (void)graph_move_spatial(ui, -1, 0);
  } else if (view->kind == view_graph && !ui->details_focused &&
      (event->key == TB_KEY_ARROW_RIGHT || event->ch == 'l')) {
    view->graph_neighbor_ready = false;
    (void)graph_move_spatial(ui, 1, 0);
  } else if (view->kind == view_graph && !ui->details_focused &&
      (event->key == TB_KEY_ARROW_UP || event->ch == 'k')) {
    view->graph_neighbor_ready = false;
    (void)graph_move_spatial(ui, 0, -1);
  } else if (view->kind == view_graph && !ui->details_focused &&
      (event->key == TB_KEY_ARROW_DOWN || event->ch == 'j')) {
    view->graph_neighbor_ready = false;
    (void)graph_move_spatial(ui, 0, 1);
  }
  else if (event->key == TB_KEY_ARROW_UP || event->ch == 'k') move_selection(ui, -1);
  else if (event->key == TB_KEY_ARROW_DOWN || event->ch == 'j') move_selection(ui, 1);
  else if (event->key == TB_KEY_PGUP) {
    scroll_detail(ui, -(tb_height() > 8 ? tb_height() - 8 : 1));
  } else if (event->key == TB_KEY_PGDN)
    scroll_detail(ui, tb_height() > 8 ? tb_height() - 8 : 1);
  else if (event->key == TB_KEY_TAB && view->kind != view_session) ui->details_focused = !ui->details_focused;
  else if (event->key == TB_KEY_TAB && view->kind == view_session) ui->details_focused = false;
  else if (event->key == TB_KEY_BACKSPACE || event->key == TB_KEY_BACKSPACE2) {
    if (ui->depth > 0) { ui->depth--; ui->details_focused = false; }
  } else if (event->ch == 'h' && ui->depth > 0 && view->kind != view_graph) { ui->depth--; ui->details_focused = false; }
  else if (event->ch == 'l' && view->kind != view_graph && !ui->details_focused) enter_selected(ui);
  else if (event->ch == 'i' && view->kind == view_graph && !ui->details_focused) inspect_graph_focus(ui);
  else if (event->ch == 'I' && view->kind == view_session) open_session_artifact(ui, false);
  else if (event->ch == 'O' && view->kind == view_session) open_session_artifact(ui, true);
  else if (event->ch == '[') {
    if (view->kind == view_graph && !ui->details_focused) graph_cycle_neighbor(ui, false);
    else switch_worker_generation(ui, -1);
  } else if (event->ch == ']') {
    if (view->kind == view_graph && !ui->details_focused) graph_cycle_neighbor(ui, true);
    else switch_worker_generation(ui, 1);
  } else if (event->key == TB_KEY_ENTER && !ui->details_focused) enter_selected(ui);
  else if (event->ch == 'q' || event->ch == 'Q') *quit = true;
  else if (event->ch == 'r' || event->ch == 'R') ui->status[0] = '\0';
  else if (event->ch == 'g' || event->ch == 'G') {
    ui->depth = 0;
    ui->details_focused = false;
    ui->help = false;
  } else if (event->ch == 'c' || event->ch == 'C') open_conversation(ui);
  else if (event->ch == 't' || event->ch == 'T') switch_view(ui, view_tables);
  else if (event->ch == 'e' || event->ch == 'E') switch_view(ui, view_events);
  else if (event->ch == 'f' || event->ch == 'F') switch_view(ui, view_failures);
  else if (event->ch == 'd') scroll_detail(ui, tb_height() > 8 ? tb_height() - 8 : 1);
  else if (event->ch == 'u') scroll_detail(ui, -(tb_height() > 8 ? tb_height() - 8 : 1));
  else if (event->ch == '?') ui->help = !ui->help;
  else if (event->key == TB_KEY_ESC) {
    if (ui->depth > 0) ui->depth--;
    else *quit = true;
  }
}

static void usage(const char *program) {
  fprintf(stderr, "Usage: %s DATABASE\n", program);
}

int main(int argc, char **argv) {
  Ui ui;
  char error[512] = "";
  bool quit = false;
  memset(&ui, 0, sizeof(ui));
  if (argc != 2 || strcmp(argv[1], "--help") == 0) {
    usage(argv[0]);
    return argc == 2 ? 0 : 2;
  }
  if (!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) {
    fprintf(stderr, "vecherinka-tui requires an interactive terminal\n");
    return 2;
  }
  if (strlen(argv[1]) >= sizeof(ui.database_path)) {
    fprintf(stderr, "database path is too long\n");
    return 2;
  }
  snprintf(ui.database_path, sizeof(ui.database_path), "%s", argv[1]);
  setlocale(LC_CTYPE, "");
  if (!open_store(&ui, error, sizeof(error))) {
    fprintf(stderr, "vecherinka-tui: %s\n", error);
    if (ui.db) sqlite3_close(ui.db);
    return 2;
  }
  sqlite3_exec(ui.db, "PRAGMA query_only=ON", NULL, NULL, NULL);
  ui.depth = 0;
  ui.views[0].kind = view_graph;
  ui.views[0].selected = -1;
  ui.views[0].graph_neighbor_outgoing = true;
  ui.views[0].graph_reveal_selection = true;
  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);
  int termbox_initialized = tb_init() == TB_OK;
  if (!termbox_initialized) {
    fprintf(stderr, "vecherinka-tui: termbox initialization failed\n");
    sqlite3_close(ui.db);
    return 2;
  }
  if (tb_set_output_mode(TB_OUTPUT_TRUECOLOR) != TB_OK) {
    fprintf(stderr, "vecherinka-tui: truecolor output mode unavailable\n");
    tb_shutdown();
    sqlite3_close(ui.db);
    return 2;
  }
  tb_set_clear_attrs(UI_FG, UI_BG);
  tb_set_input_mode(TB_INPUT_ESC);
  render(&ui);
  while (!quit && !stop_requested) {
    struct tb_event event;
    int rc = tb_peek_event(&event, 1000);
    if (rc == TB_OK) {
      if (event.type == TB_EVENT_KEY) handle_key(&ui, &event, &quit);
      else if (event.type == TB_EVENT_RESIZE) {
        if (ui.views[ui.depth].kind == view_graph)
          ui.views[ui.depth].graph_reveal_selection = true;
      }
    } else if (rc != TB_ERR_NO_EVENT) {
      snprintf(ui.status, sizeof(ui.status), "terminal input failed: %d", rc);
      draw_refresh_error(&ui);
      break;
    }
    if (!render(&ui)) draw_refresh_error(&ui);
  }
  tb_shutdown();
  sqlite3_close(ui.db);
  for (int i = 0; i < ui.chat_count; ++i) {
    free(ui.chat[i].text);
    free(ui.chat[i].events);
  }
  free(ui.chat);
  return 0;
}
