"""Usage: BENCH_PHOTOS_DIR=/folder/with/photos python3 smoothness_swift_engine.py (needs swift_bench_paths.txt, one folder per line, next to this file).
Smoothness, harder: three interleaved rounds per mode, and a foreground job that itself does heavy disk work
(write 3 GB and fsync, then 1,500 random cold small reads) timed idle, next to dupes.py default, and next to --fast."""
import os, sys, re, json, time, random, signal, ctypes, fcntl, threading, subprocess, statistics
S = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(S)
lib = ctypes.CDLL("/usr/lib/libproc.dylib")
MODES = {"idle": None, "default": [], "fast": ["--workers", "8"]}

def pct(xs, q):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(len(xs) * q))]

def rusage_read(pid):
    b = (ctypes.c_uint64 * 80)()
    return None if lib.proc_pid_rusage(pid, 4, ctypes.byref(b)) else b[18]

PHOTOS = []
for r, d, fs in os.walk(os.environ.get("BENCH_PHOTOS_DIR", os.path.expanduser("~/Pictures"))):
    PHOTOS += [os.path.join(r, f) for f in fs if f.lower().endswith((".jpg", ".jpeg", ".png", ".tif", ".tiff", ".heic", ".cr2", ".dng"))]
    if len(PHOTOS) > 6000: break
PHOTOS = [p for p in PHOTOS if os.path.getsize(p) > 300_000]
random.seed(11)

def start(mode):
    flags = MODES[mode]
    if flags is None: return None
    p = subprocess.Popen([ROOT + "/.build/release/dupecheck", S + "/swift_bench_paths.txt", "--min-size", "10240"] + flags, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(10); return p

def stop(p):
    if p:
        p.send_signal(signal.SIGINT)
        try: p.wait(30)
        except subprocess.TimeoutExpired: p.kill()
    time.sleep(8)

def probe(seconds):
    io, jit, stop_at = [], [], time.time() + seconds
    def jt():
        while time.time() < stop_at:
            t = time.perf_counter(); time.sleep(0.005); jit.append((time.perf_counter() - t - 0.005) * 1000)
    th = threading.Thread(target=jt); th.start()
    while time.time() < stop_at:
        f = random.choice(PHOTOS); fd = os.open(f, os.O_RDONLY); fcntl.fcntl(fd, 48, 1)
        off = random.randrange(0, max(4096, os.fstat(fd).st_size - 65536)) // 4096 * 4096
        t = time.perf_counter(); os.pread(fd, 65536, off); io.append((time.perf_counter() - t) * 1000); os.close(fd); time.sleep(0.1)
    th.join(); return io, jit

def probe_round(mode):
    p = start(mode); r0 = rusage_read(p.pid) if p else 0; t0 = time.time()
    io, jit = probe(30); el = time.time() - t0; r1 = rusage_read(p.pid) if p else 0; stop(p)
    return dict(mode=mode, tool_gb_s=round(((r1 or 0) - (r0 or 0)) / el / 1e9, 2), io_p50=round(pct(io, .5), 2), io_p99=round(pct(io, .99), 2), io_max=round(max(io), 1), jit_p99=round(pct(jit, .99), 2), jit_max=round(max(jit), 1))

def foreground_job():
    scratch = S + "/fg_scratch.bin"; chunk = os.urandom(1 << 20); t = time.perf_counter()
    fd = os.open(scratch, os.O_WRONLY | os.O_CREAT | os.O_TRUNC)
    for _ in range(3072): os.write(fd, chunk)
    os.fsync(fd); os.close(fd); t_write = time.perf_counter() - t; os.unlink(scratch)
    t = time.perf_counter()
    for _ in range(1500):
        f = random.choice(PHOTOS); fd = os.open(f, os.O_RDONLY); fcntl.fcntl(fd, 48, 1)
        os.pread(fd, 65536, random.randrange(0, max(4096, os.fstat(fd).st_size - 65536)) // 4096 * 4096); os.close(fd)
    t_read = time.perf_counter() - t
    return dict(write_3gb_s=round(t_write, 2), small_reads_1500_s=round(t_read, 2))

def job_round(mode):
    p = start(mode); j = foreground_job(); stop(p); j["mode"] = mode; return j

results = dict(probe=[], job=[])
order = ["idle", "default", "fast"]
for rnd in range(3):
    rot = order[rnd % 3:] + order[:rnd % 3]
    for m in rot:
        row = probe_round(m); row["round"] = rnd; results["probe"].append(row); print(json.dumps(row), flush=True)
for rnd in range(3):
    rot = order[rnd % 3:] + order[:rnd % 3]
    for m in rot:
        row = job_round(m); row["round"] = rnd; results["job"].append(row); print(json.dumps(row), flush=True)
json.dump(results, open(S + "/smooth_results_swift.json", "w"), indent=1)
print("DONE", flush=True)
