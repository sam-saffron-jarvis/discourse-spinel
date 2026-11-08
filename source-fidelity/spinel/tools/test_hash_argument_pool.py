#!/usr/bin/env python3
"""Exercise the compiler's actual hash-argument memo at allocation boundaries.

The small C carrier isolates the memo from the rest of inference; its fake node
index supplies either no call or one call. The production memo code is extracted
unchanged from analyze.c, compiled under ASan/UBSan, and invoked at a full pool.
Run from any directory: python3 tools/test_hash_argument_pool.py
"""
import argparse
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source", type=Path, default=ROOT / "src/analyze.c",
                    help="optional baseline analyze.c for a red/green check")
source = parser.parse_args().source.read_text()
start = source.index("typedef struct { char *name; int pidx, off; } HlaSlot;")
end = source.index("static int hls_join(", start)
memo = source[start:end]
carrier = r'''
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { int unused; } NodeTable;
typedef struct { NodeTable *nt; } Compiler;
#define NK_CallNode 1
static int supplies_argument;
static unsigned sp_strhash(const char *s) {
  unsigned h = 2166136261u;
  for (; *s; s++) h = (h ^ (unsigned char)*s) * 16777619u;
  return h;
}
static int sp_streq(const char *a, const char *b) { return strcmp(a, b) == 0; }
static const char *current_name;
static int an_calls_named_first(Compiler *c, const char *name) {
  (void)c; current_name = name; return supplies_argument ? 0 : -1;
}
static int an_calls_named_next(int id) { (void)id; return -1; }
static int nt_kind(const NodeTable *nt, int id) { (void)nt; (void)id; return NK_CallNode; }
static const char *nt_str(const NodeTable *nt, int id, const char *key) {
  (void)nt; (void)id; (void)key; return current_name;
}
static int nt_ref(const NodeTable *nt, int id, const char *key) {
  (void)nt; (void)id; (void)key; return 0;
}
static const int *nt_arr(const NodeTable *nt, int id, const char *key, int *count) {
  static int argument = 91;
  (void)nt; (void)id; (void)key; *count = 1; return &argument;
}
'''
checks = r'''
static void full_pool(void) {
  hla_reset();
  free(hla_pool);
  hla_pcap = hla_pn = 1;
  hla_pool = malloc(sizeof(int));
  assert(hla_pool);
  hla_pool[0] = 0;
}
int main(void) {
  NodeTable nt = {0}; Compiler c = {&nt};
  supplies_argument = 0;
  full_pool();
  int off = hla_args(&c, "empty", 0);
  assert(off == 1 && hla_pool[off] == 0 && hla_pn <= hla_pcap);
  assert(hla_args(&c, "empty", 0) == off);
  supplies_argument = 1;
  full_pool();
  off = hla_args(&c, "one", 0);
  assert(hla_pool[off] == 1 && hla_pool[off + 1] == 91 && hla_pn <= hla_pcap);
  supplies_argument = 0;
  full_pool();
  for (int i = 0; i < 4097; i++) {
    char name[40]; snprintf(name, sizeof name, "empty_%d", i);
    off = hla_args(&c, name, 0);
    assert(hla_pool[off] == 0 && hla_pn <= hla_pcap);
  }
  hla_reset(); free(hla_pool); free(hla_slot);
  puts("hash-argument pool: empty/header, payload, memo and repeated growth PASS");
  return 0;
}
'''
with tempfile.TemporaryDirectory(prefix="spinel-hash-argument-pool-") as tmp:
    path = Path(tmp)
    (path / "test.c").write_text(carrier + memo + checks)
    command = shlex.split(os.environ.get("CC", "cc"))
    subprocess.run(command + ["-std=gnu11", "-g", "-O1", "-fsanitize=address,undefined",
                   "-fno-omit-frame-pointer", str(path / "test.c"), "-o", str(path / "test")], check=True)
    env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0:halt_on_error=1", UBSAN_OPTIONS="halt_on_error=1")
    subprocess.run([str(path / "test")], env=env, check=True)
