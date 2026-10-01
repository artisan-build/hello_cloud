/*
 * ./app for a language whose compiler produces a DIRECTORY.
 *
 * The pipeline this repo uses carries exactly one file per branch: GitHub
 * Actions publishes `app`, Laravel Cloud's build command downloads `app`, and
 * Cloud's Go runtime starts `./app`. CI also insists that `app` is a
 * linux/arm64 ELF, which rules out a shell script. A PackageCompiler app is
 * none of those things: it is a tree with a launcher, a sysimage, libjulia and
 * a dozen shared libraries.
 *
 * So this program IS ./app. A gzipped tar of the bundle is appended to it at
 * build time, and build.sh compiles this file with -DPAYLOAD_LEN=<that
 * tarball's size>, so the payload starts at (own size - PAYLOAD_LEN). At
 * startup it reads its own image through /proc/self/exe, pipes the payload
 * into tar, and execs the bundle's launcher. The extraction happens once per
 * container: the marker file makes a restart skip it.
 *
 * Nothing about any other branch, or any shared file, had to change for this.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifndef PAYLOAD_LEN
#error "compile with -DPAYLOAD_LEN=<bytes of appended tarball>"
#endif

/* A fixed path, not mkdtemp: a crash-looping container would otherwise fill
 * the disk with copies of a 300 MB bundle. */
#define ROOT "/tmp/hello_cloud-julia"
#define MARKER ROOT "/.extracted"
#define LAUNCHER ROOT "/bin/HelloCloud"

static void die(const char *what)
{
    fprintf(stderr, "hello_cloud: %s: %s\n", what, strerror(errno));
    exit(1);
}

/* Pipes the appended payload into `tar -xzf - -C ROOT`. */
static void extract(int self, off_t start, uint64_t len)
{
    if (mkdir(ROOT, 0755) != 0 && errno != EEXIST)
        die("mkdir " ROOT);

    int fds[2];
    if (pipe(fds) != 0)
        die("pipe");

    pid_t child = fork();
    if (child < 0)
        die("fork");

    if (child == 0) {
        close(fds[1]);
        if (dup2(fds[0], STDIN_FILENO) < 0)
            die("dup2");
        close(fds[0]);
        execlp("tar", "tar", "-xzf", "-", "-C", ROOT, (char *)NULL);
        die("exec tar");
    }

    close(fds[0]);
    if (lseek(self, start, SEEK_SET) < 0)
        die("lseek");

    char buf[1 << 16];
    uint64_t left = len;
    while (left > 0) {
        size_t want = left < sizeof buf ? (size_t)left : sizeof buf;
        ssize_t got = read(self, buf, want);
        if (got <= 0)
            die("read payload");
        char *p = buf;
        ssize_t n = got;
        while (n > 0) {
            ssize_t wrote = write(fds[1], p, (size_t)n);
            if (wrote <= 0) {
                if (wrote < 0 && errno == EINTR)
                    continue;
                die("write to tar");
            }
            p += wrote;
            n -= wrote;
        }
        left -= (uint64_t)got;
    }
    close(fds[1]);

    int status = 0;
    if (waitpid(child, &status, 0) < 0)
        die("waitpid");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "hello_cloud: tar failed (status %d)\n", status);
        exit(1);
    }

    int marker = open(MARKER, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (marker < 0)
        die("open " MARKER);
    close(marker);
}

int main(int argc, char **argv)
{
    int self = open("/proc/self/exe", O_RDONLY);
    if (self < 0)
        die("open /proc/self/exe");

    off_t size = lseek(self, 0, SEEK_END);
    if (size < 0)
        die("lseek end");

    off_t start = size - (off_t)PAYLOAD_LEN;
    if (start <= 0) {
        fprintf(stderr, "hello_cloud: this binary is %lld bytes, too small to "
                        "hold a %lld-byte payload\n",
                (long long)size, (long long)PAYLOAD_LEN);
        return 1;
    }

    struct stat st;
    if (stat(MARKER, &st) != 0)
        extract(self, start, (uint64_t)PAYLOAD_LEN);
    close(self);

    /* The bundle's launcher replaces this process, so Cloud's start command
     * still has exactly one process to supervise. */
    execv(LAUNCHER, argv);
    (void)argc;
    die("exec " LAUNCHER);
    return 1;
}
