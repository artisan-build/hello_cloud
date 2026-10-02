/*
 * tools/sfx/bootstrap.c -- the canonical self-extracting launcher.
 *
 * Why it exists: the pipeline carries exactly ONE release asset called `app`,
 * and .github/workflows/build.yml requires that asset to be a linux/arm64 ELF.
 * A language that ships its own runtime builds a DIRECTORY (an OTP release, a
 * jlink image, a Forth engine plus its image and library tree), not a single
 * executable. So `app` becomes this ELF with a gzipped tar of the bundle
 * appended to it, plus a 40-byte trailer saying where the tar starts:
 *
 *     [ this ELF ][ bundle.tar.gz ][ 24-byte magic ][ 16-digit offset ]
 *
 * Appending data to an ELF leaves it a valid, runnable ELF -- the program
 * headers describe what the loader maps and it ignores the rest -- so `file`
 * still says "ELF ... ARM aarch64" and CI is satisfied without knowing
 * anything new. At startup this reads its own file, streams the tail through
 * `tar -xz`, and execs the bundle's entry script. Only tar and gzip are needed
 * at run time, and Debian 12 (Cloud's runtime image) has both.
 *
 * Build it with tools/sfx/pack.sh, which also appends the trailer.
 *
 * Two deliberate choices, both measured on Cloud:
 *
 *  - The launcher is linked -static, so nothing about the host's glibc can
 *    break the one thing that has to run first.
 *
 *  - It unpacks BESIDE ./app, not into /tmp, falling back to /tmp only when
 *    the executable's own directory is not writable. On many container hosts
 *    /tmp is a tmpfs and every byte of a 60 MB bundle would be charged to a
 *    256 MB instance. (On Cloud, /var/www/html and /tmp both measured as
 *    `overlay`, so this costs disk and not memory either way -- but the
 *    bundle's own directory is the one that is guaranteed not to be a tmpfs.)
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAGIC "HELLO_CLOUD_SFX_TRAILER1"
#define MAGIC_LEN 24
#define OFF_LEN 16
#define TRAILER_LEN (MAGIC_LEN + OFF_LEN)

/* Laravel Cloud hands the app process RLIMIT_NOFILE = 1,073,741,816. Runtimes
 * that size a table from the fd limit -- the BEAM's port table is the one we
 * measured -- then try to allocate on the order of a gigabyte and are
 * OOM-killed by the cgroup before printing a single line, at ANY instance
 * size. Cloud reports "your application ran out of memory", and more memory
 * never helps. Reproduced exactly with
 *
 *     docker run --memory=256m --ulimit nofile=1073741816 debian:12 /app
 *
 * which dies with exit 137, while the same command under
 * `sh -c 'ulimit -n 65536; exec /app'` answers in five seconds at 114 MiB RSS.
 *
 * Lowering a soft limit never needs privileges, and the hard limit is left
 * alone, so a process that really wants more fds can still raise its own.
 * Doing it here rather than in each bundle's run script means every language
 * that uses this launcher gets the fix whether or not its entry point is a
 * shell script. SFX_KEEP_NOFILE=1 opts out.
 */
#define SFX_NOFILE_SOFT 65536

static void cap_nofile(void) {
    const char *keep = getenv("SFX_KEEP_NOFILE");
    if (keep && *keep && strcmp(keep, "0") != 0) return;

    struct rlimit rl;
    if (getrlimit(RLIMIT_NOFILE, &rl) != 0) return;
    if (rl.rlim_cur != RLIM_INFINITY && rl.rlim_cur <= SFX_NOFILE_SOFT) return;

    rlim_t want = SFX_NOFILE_SOFT;
    if (rl.rlim_max != RLIM_INFINITY && rl.rlim_max < want) want = rl.rlim_max;
    rlim_t was = rl.rlim_cur;
    rl.rlim_cur = want;
    if (setrlimit(RLIMIT_NOFILE, &rl) == 0)
        fprintf(stderr, "sfx: RLIMIT_NOFILE soft %llu -> %llu\n",
                (unsigned long long)was, (unsigned long long)want);
}

#ifndef SFX_SLUG
#define SFX_SLUG "bundle"
#endif
#ifndef SFX_ENTRY
#define SFX_ENTRY "run"
#endif

static void die(const char *what) {
    fprintf(stderr, "sfx: %s: %s\n", what, strerror(errno));
    exit(1);
}

int main(int argc, char **argv) {
    char self[4096];
    ssize_t n = readlink("/proc/self/exe", self, sizeof self - 1);
    if (n < 0) die("readlink /proc/self/exe");
    self[n] = '\0';

    FILE *f = fopen(self, "rb");
    if (!f) die("open self");
    if (fseek(f, -(long)TRAILER_LEN, SEEK_END) != 0) die("seek trailer");

    char trailer[TRAILER_LEN + 1];
    if (fread(trailer, 1, TRAILER_LEN, f) != TRAILER_LEN) die("read trailer");
    trailer[TRAILER_LEN] = '\0';
    if (memcmp(trailer, MAGIC, MAGIC_LEN) != 0) {
        fprintf(stderr, "sfx: no bundle appended to %s\n", self);
        return 1;
    }
    long off = strtol(trailer + MAGIC_LEN, NULL, 10);

    long end = ftell(f);
    if (end < 0) die("tell");
    long payload = end - TRAILER_LEN - off;
    if (off <= 0 || payload <= 0) {
        fprintf(stderr, "sfx: bad trailer (offset %ld, payload %ld)\n", off, payload);
        return 1;
    }

    char dir[8192];
    const char *root = getenv("SFX_DIR");
    if (root && *root) {
        snprintf(dir, sizeof dir, "%s", root);
    } else {
        char base[4096];
        snprintf(base, sizeof base, "%s", self);
        char *slash = strrchr(base, '/');
        if (slash) *slash = '\0'; else snprintf(base, sizeof base, ".");
        snprintf(dir, sizeof dir, "%s/.hc-sfx-" SFX_SLUG, base);
        if (mkdir(dir, 0755) != 0 && errno != EEXIST)
            snprintf(dir, sizeof dir, "/tmp/hc-sfx-" SFX_SLUG);
    }

    /* The marker is written last, so a half-finished unpack is never reused. */
    char ready[8400];
    snprintf(ready, sizeof ready, "%s/.sfx-ready", dir);
    struct stat st;
    if (stat(ready, &st) != 0) {
        if (mkdir(dir, 0755) != 0 && errno != EEXIST) die("mkdir bundle dir");

        char cmd[9000];
        snprintf(cmd, sizeof cmd, "exec tar -xzf - -C '%s'", dir);
        FILE *tar = popen(cmd, "w");
        if (!tar) die("popen tar");

        if (fseek(f, off, SEEK_SET) != 0) die("seek payload");
        char buf[65536];
        long left = payload;
        while (left > 0) {
            size_t want = (size_t)(left < (long)sizeof buf ? left : (long)sizeof buf);
            size_t got = fread(buf, 1, want, f);
            if (got == 0) die("read payload");
            if (fwrite(buf, 1, got, tar) != got) die("write to tar");
            left -= (long)got;
        }
        int rc = pclose(tar);
        if (rc != 0) {
            fprintf(stderr, "sfx: tar exited %d\n", rc);
            return 1;
        }
        FILE *m = fopen(ready, "w");
        if (m) fclose(m);
        fprintf(stderr, "sfx: unpacked %ld bytes of " SFX_SLUG " into %s\n", payload, dir);
    } else {
        fprintf(stderr, "sfx: reusing the bundle already in %s\n", dir);
    }
    fclose(f);

    cap_nofile();

    char entry[8400];
    snprintf(entry, sizeof entry, "%s/" SFX_ENTRY, dir);
    if (setenv("SFX_ROOT", dir, 1) != 0) die("setenv SFX_ROOT");

    /* exec, not fork: the real server becomes this process, so it is PID 1's
     * own child, sees the original argv, and receives signals directly. */
    argv[0] = entry;
    execv(entry, argv);
    (void)argc;
    die("exec the bundle entry point");
    return 1;
}
