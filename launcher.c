/* app: a self-extracting launcher for a runtime that ships as a directory.
 *
 * Laravel Cloud's build command has to leave ONE executable at ./app, and the
 * build workflow checks that file is a linux/arm64 ELF before it publishes it.
 * A runtime whose artifact is a directory therefore travels inside this little
 * C program: the whole bundle is a tar.gz linked in as a blob, unpacked once
 * into a private directory under $TMPDIR on the first start, and the real
 * entry point is exec'd in place of this process -- so the server, not this
 * launcher, is PID 1's child and sees the original argv.
 *
 * The build writes bundle.tar.gz and bundle_config.h (BUNDLE_ID, which
 * carries the bundle's own sha256, and BUNDLE_ENTRY, the entry point inside
 * it) next to these two files and then compiles them:
 *
 *     gcc -O2 -o app launcher.c bundle.S
 *
 * Only tar and gzip are needed at run time, and Debian 12 -- Cloud's runtime
 * image -- has both.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* Written by the build: BUNDLE_ID and BUNDLE_ENTRY. */
#include "bundle_config.h"

/* Defined by bundle.S: the embedded tar.gz. */
extern const char bundle_start[];
extern const char bundle_end[];

int main(int argc, char **argv)
{
    (void)argc;

    const char *tmp = getenv("TMPDIR");
    if (tmp == NULL || *tmp == '\0')
        tmp = "/tmp";

    char dir[PATH_MAX], stamp[PATH_MAX], entry[PATH_MAX], cmd[PATH_MAX + 64];
    snprintf(dir, sizeof dir, "%s/hello_cloud-%s", tmp, BUNDLE_ID);
    snprintf(stamp, sizeof stamp, "%s/.unpacked", dir);
    snprintf(entry, sizeof entry, "%s/%s", dir, BUNDLE_ENTRY);

    /* BUNDLE_ID carries the bundle's own hash, so a stamp that is already
       there was written by an identical bundle and the unpack can be skipped.
       Cloud gives each instance a fresh filesystem, so in practice this runs
       exactly once per instance. */
    if (access(stamp, F_OK) != 0) {
        if (mkdir(dir, 0700) != 0 && errno != EEXIST) {
            fprintf(stderr, "app: mkdir %s: %s\n", dir, strerror(errno));
            return 70;
        }
        snprintf(cmd, sizeof cmd, "tar -xzf - -C '%s'", dir);
        FILE *tar = popen(cmd, "w");
        if (tar == NULL) {
            fprintf(stderr, "app: popen tar: %s\n", strerror(errno));
            return 70;
        }
        size_t n = (size_t)(bundle_end - bundle_start);
        if (fwrite(bundle_start, 1, n, tar) != n) {
            fprintf(stderr, "app: writing the bundle to tar: %s\n", strerror(errno));
            pclose(tar);
            return 70;
        }
        if (pclose(tar) != 0) {
            fprintf(stderr, "app: tar could not unpack the bundle into %s\n", dir);
            return 70;
        }
        FILE *s = fopen(stamp, "w");
        if (s != NULL)
            fclose(s);
    }

    /* The bundled program works out where its own library tree is from
       argv[0], so it has to see the unpacked path, not "./app". */
    argv[0] = entry;
    execv(entry, argv);
    fprintf(stderr, "app: exec %s: %s\n", entry, strerror(errno));
    return 70;
}
