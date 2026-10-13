# -*- coding: utf-8 -*-
import lupa
import time

lua = lupa.LuaRuntime()

test_script = r"""
package.path = package.path .. ';./?.lua;./modules/?.lua'
local parser = require('parser')

function benchmark_content(content, filename)
  local t0 = os.clock()
  local res = parser.parse(content, filename)
  local t1 = os.clock()
  local elapsed = t1 - t0

  local info = {
    filename = filename,
    ok = res.ok,
    format = res.format,
    time_sec = elapsed,
    time_ms = elapsed * 1000,
    subtitles_count = #res.subtitles,
    actors_count = #res.actors,
    actors = res.actors,
    actor_counts = res.actor_counts,
    first_sub = res.subtitles[1],
    last_sub = res.subtitles[#res.subtitles]
  }
  return info
end
"""

lua.execute(test_script)
bench_fn = lua.eval('benchmark_content')

files_to_test = [
    "examples/Koori_no_Jouheki_single_actor.srt",
    "examples/movie_length_with_actors.ass",
    "examples/movie_length_with_actors.srt",
    "examples/movie_length_no_actors.ass",
    "examples/movie_length_no_actors.srt",
    "examples/02 субтитры Koori no Jouheki 2nd Season.ass",
    "examples/Город Жун 6.ass",
    "examples/3.srt",
    "examples/Ёдзакура2.8 SKIDEN.srt"
]

print("=" * 70)
print(f"{'FILE':<40} | {'FORMAT':<6} | {'SUBS':<6} | {'ACTORS':<6} | {'TIME (ms)':<9}")
print("=" * 70)

for fpath in files_to_test:
    with open(fpath, 'rb') as f:
        content = f.read()
    
    fname = fpath.split('/')[-1]
    res = bench_fn(content, fname)

    time_ms = f"{res['time_ms']:.2f}"
    print(f"{fname:<40} | {res['format']:<6} | {res['subtitles_count']:<6} | {res['actors_count']:<6} | {time_ms:>7} ms")

print("=" * 70)

# Detailed analysis on the generated test files
print("\n--- DETAILED ANALYSIS OF GENERATED FILES ---\n")
for fpath in files_to_test[:5]:
    with open(fpath, 'rb') as f:
        content = f.read()
    fname = fpath.split('/')[-1]
    res = bench_fn(content, fname)
    print(f"File: {fname}")
    print(f"  Format: {res['format']}, Subtitles: {res['subtitles_count']}, Parse Time: {res['time_ms']:.2f} ms")
    print(f"  First Sub: [{res['first_sub']['start_time']:.2f} - {res['first_sub']['end_time']:.2f}] Actor: '{res['first_sub']['actor']}' | Text: '{res['first_sub']['text'][:40]}...'")
    print(f"  Last Sub:  [{res['last_sub']['start_time']:.2f} - {res['last_sub']['end_time']:.2f}] Actor: '{res['last_sub']['actor']}' | Text: '{res['last_sub']['text'][:40]}...'")
    if res['actors_count'] > 0:
        print(f"  Actors ({res['actors_count']}):")
        for i, a in enumerate(res['actors'].values(), 1):
            cnt = res['actor_counts'][a]
            print(f"    {i}. {a}: {cnt} lines")
    print()
