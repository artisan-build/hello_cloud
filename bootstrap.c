/*
 * bootstrap.c -- a self-extracting launcher.
 *
 * Why this exists: this language ships its own runtime, so the build product is
 * a DIRECTORY (an OTP release, a jlink image + jar), not one executable. The
 * pipeline carries exactly one release asset called `app`, and CI requires that
 * asset to be a linux/arm64 ELF. So `app` is this ELF with a gzipped tar of the
 * bundle appended to it, plus a 40-byte trailer saying where the tar starts.
 *
 *     [ this ELF ][ bundle.tar.gz ][ 24-byte magic ][ 16-digit offset ]
 *
 * Appending data to an ELF leaves it a valid, runnable ELF: the program headers
 * describe the parts the loader maps and it ignores the rest. At startup we
 * read our own file, stream the tail through `tar -xz`, and exec the bundle's
 * own entry script. No shared file in the repo changes.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAGIC "HELLO_CLOUD_SFX_TRAILER1"
#define MAGIC_LEN 24
#define OFF_LEN 16
#define TRAILER_LEN (MAGIC_LEN + OFF_LEN)

#ifndef SFX_SLUG
#define SFX_SLUG "bundle"
#endif
#ifndef SFX_ENTRY
#define SFX_ENTRY "run"
#endif

static void die(const char *what) {
    fprintf(stderr, "bootstrap: %s: %s\n", what, strerror(errno));
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
        fprintf(stderr, "bootstrap: no bundle appended to %s\n", self);
        return 1;
    }
    long off = strtol(trailer + MAGIC_LEN, NULL, 10);

    long end = ftell(f);
    if (end < 0) die("tell");
    long payload = end - TRAILER_LEN - off;
    if (off <= 0 || payload <= 0) {
        fprintf(stderr, "bootstrap: bad trailer (offset %ld, payload %ld)\n", off, payload);
        return 1;
    }

    /* Unpack NEXT TO the executable by default, not into /tmp: on a container
     * host /tmp is often a tmpfs, so every byte of the bundle would be charged
     * to the instance's memory. SFX_DIR overrides, and /tmp is the fallback if
     * the executable's own directory is not writable. */
    char dir[4096];
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

    char ready[4200];
    snprintf(ready, sizeof ready, "%s/.sfx-ready", dir);
    struct stat st;
    if (stat(ready, &st) != 0) {
        if (mkdir(dir, 0755) != 0 && errno != EEXIST) die("mkdir bundle dir");

        char cmd[8500];
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
            fprintf(stderr, "bootstrap: tar exited %d\n", rc);
            return 1;
        }
        FILE *m = fopen(ready, "w");
        if (m) fclose(m);
        fprintf(stderr, "bootstrap: unpacked %ld bytes of " SFX_SLUG " bundle into %s\n", payload, dir);
    } else {
        fprintf(stderr, "bootstrap: reusing bundle already in %s\n", dir);
    }
    fclose(f);

    char entry[4300];
    snprintf(entry, sizeof entry, "%s/" SFX_ENTRY, dir);
    if (setenv("SFX_ROOT", dir, 1) != 0) die("setenv SFX_ROOT");

    argv[0] = entry;
    execv(entry, argv);
    (void)argc;
    die("exec bundle entry point");
    return 1;
}
