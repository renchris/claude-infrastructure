/* cc-shim: run a #! script without the kernel's #! path. macOS 15 keeps ~1.1 KiB of kernel memory
   per #! exec until reboot; a compiled exec of the interpreter costs +0.020 +/- 0.017
   (docs/research/kalloc-longterm-2026-10-21/shim.md §3, T-1).

   It reads the target's #! line exactly as xnu exec_shell_imgact + exec_extract_strings do and
   execve()s the interpreter with the target as an argument. It never forks and installs no signal
   handler, so pid, fds, signal state and exit status are the interpreter's own.

   Mode by the name it was exec'd as (apple[] executable_path, unresolved, so a symlink keeps its name):
     <N>      stub:     run <parent>/.<dir>-real/<N> [args]     /x/stub/jq -> /x/.stub-real/jq
     cc-exec  explicit: cc-exec <script> [args]
     cc-shim  --selftest | --version
   Exit 127 = no target / interpreter not found, 126 = refused or not executable (the shell's codes).
   libSystem only. */
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef CC_SHIM_HASH
#define CC_SHIM_HASH "unbuilt"
#endif

#define IMG_SHSIZE 512 /* bsd/sys/imgact.h: the kernel looks for the EOL in this many bytes */
#define MAX_TOKENS (IMG_SHSIZE / 2 + 1)
#define MAX_HOPS 16
#define DEFAULT_PATH "/usr/bin:/bin:/usr/sbin:/sbin"
/* kern_exec.c: whitespace is space/tab ONLY (CR stays in the token); '#' ends the line like '\n'. */
#define IS_WHITESPACE(ch) ((ch) == ' ' || (ch) == '\t')
#define IS_EOL(ch) ((ch) == '#' || (ch) == '\n')

enum { SB_NOINTERP = -1, SB_NOEOL = -2 };

__attribute__((noreturn, format(printf, 2, 3))) static void die(int rc, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fputs("cc-shim: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
    exit(rc);
}

static int exec_rc(int e) { return e == ENOENT ? 127 : 126; }

/* vdata: IMG_SHSIZE bytes starting "#!", zero past EOF (the kernel's page buffer is zeroed, so a
   short file whose line lacks '\n' never finds an EOL). line: IMG_SHSIZE bytes of scratch the tokens
   point into. Returns the token count, SB_NOINTERP or SB_NOEOL (both ENOEXEC in the kernel). */
static int parse_shebang(const char *vdata, char *line, char **tok) {
    const char *ihp = vdata + 2, *end = vdata + IMG_SHSIZE, *start;
    for (; ihp < end; ihp++) {
        if (IS_EOL(*ihp)) return SB_NOINTERP;
        if (!IS_WHITESPACE(*ihp)) break;
    }
    if (ihp == end) return SB_NOINTERP;
    start = ihp;
    while (ihp < end && !IS_EOL(*ihp)) ihp++;
    if (ihp == end) return SB_NOEOL;
    while (IS_EOL(*ihp) || IS_WHITESPACE(*ihp)) ihp--; /* stops at start: it is neither */
    size_t n = (size_t)(ihp + 1 - start);
    memcpy(line, start, n); /* byte copy like the kernel's: an embedded NUL truncates below */
    line[n] = '\0';
    /* exec_extract_strings: split the C string on whitespace, every word its own argv entry. */
    int k = 0;
    char *a = line;
    while (a) {
        char *ch = a;
        while (*ch && !IS_WHITESPACE(*ch)) ch++;
        tok[k++] = a;
        if (*ch == '\0') {
            a = NULL;
        } else {
            *ch = '\0';
            a = ch + 1;
            while (IS_WHITESPACE(*a)) a++;
        }
    }
    return k;
}

static int is_macho(const char *b, ssize_t n) {
    uint32_t m;
    if (n < 4) return 0;
    memcpy(&m, b, 4);
    return m == 0xfeedfaceu || m == 0xcefaedfeu || m == 0xfeedfacfu || m == 0xcffaedfeu ||
           m == 0xcafebabeu || m == 0xbebafecau;
}

/* Up to `want` bytes from fd; -1 on a read error. */
static ssize_t read_head(int fd, char *buf, size_t want) {
    size_t got = 0;
    while (got < want) {
        ssize_t r = read(fd, buf + got, want - got);
        if (r < 0 && errno == EINTR) continue;
        if (r < 0) return -1;
        if (r == 0) break;
        got += (size_t)r;
    }
    return (ssize_t)got;
}

/* Up to `want` bytes of a file's head; -1 if it cannot be opened or read. */
static ssize_t peek(const char *path, char *buf, size_t want) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    ssize_t n = read_head(fd, buf, want);
    int e = errno;
    close(fd);
    errno = e;
    return n;
}

/* /x/stub/jq -> /x/.stub-real/jq. 0 on success, -1 if it does not fit. */
static int derive_target(const char *dir, const char *name, char *out, size_t outsz) {
    size_t dl = strlen(dir);
    while (dl > 1 && dir[dl - 1] == '/') dl--;
    size_t cut = dl;
    while (cut > 0 && dir[cut - 1] != '/') cut--;
    /* cut: length of "<parent>/"; the parent keeps its own slash, so "/stub" -> "/.stub-real". */
    int w = snprintf(out, outsz, "%.*s.%.*s-real/%s", (int)cut, dir, (int)(dl - cut), dir + cut, name);
    return (w < 0 || (size_t)w >= outsz) ? -1 : 0;
}

static int needs_realpath(const char *d) {
    size_t n = strlen(d);
    if (d[0] != '/' || strstr(d, "/./") || strstr(d, "/../")) return 1;
    return (n >= 2 && !strcmp(d + n - 2, "/.")) || (n >= 3 && !strcmp(d + n - 3, "/.."));
}

/* `#!/usr/bin/env cmd`: resolve cmd on the CALLER's PATH as env's execvp would, first regular
   executable file wins. Empty PATH element = cwd. 0 and `out` filled, or -1. */
static int path_lookup(const char *cmd, char *out, size_t outsz) {
    const char *p = getenv("PATH");
    if (!p) p = DEFAULT_PATH;
    for (;;) {
        const char *c = strchr(p, ':');
        size_t l = c ? (size_t)(c - p) : strlen(p);
        int w = l ? snprintf(out, outsz, "%.*s/%s", (int)l, p, cmd) : snprintf(out, outsz, "./%s", cmd);
        struct stat st;
        if (w > 0 && (size_t)w < outsz && stat(out, &st) == 0 && S_ISREG(st.st_mode) &&
            access(out, X_OK) == 0)
            return 0;
        if (!c) return -1;
        p = c + 1;
    }
}

/* ---- selftest: shebang lines through the parser, plus target derivation ---- */
struct sb_case {
    const char *line;
    size_t len;  /* 0 = strlen */
    const char *want; /* tokens joined by '|', or "NOINTERP" / "NOEOL" */
};

static int check_case(const char *line, size_t len, const char *want, int idx) {
    char vdata[IMG_SHSIZE], buf[IMG_SHSIZE], got[IMG_SHSIZE * 2];
    char *tok[MAX_TOKENS];
    memset(vdata, 0, sizeof vdata);
    memcpy(vdata, line, len < IMG_SHSIZE ? len : IMG_SHSIZE);
    int k = parse_shebang(vdata, buf, tok);
    if (k == SB_NOINTERP) {
        snprintf(got, sizeof got, "NOINTERP");
    } else if (k == SB_NOEOL) {
        snprintf(got, sizeof got, "NOEOL");
    } else {
        got[0] = '\0';
        for (int i = 0; i < k; i++) {
            if (i) strlcat(got, "|", sizeof got);
            strlcat(got, tok[i], sizeof got);
        }
    }
    if (strcmp(got, want) == 0) return 0;
    fprintf(stderr, "cc-shim selftest: case %d: want [%s] got [%s]\n", idx, want, got);
    return 1;
}

static int selftest(void) {
    static const struct sb_case cases[] = {
        {"#!/bin/sh\n", 0, "/bin/sh"},
        {"#!/bin/bash -e\n", 0, "/bin/bash|-e"},
        {"#! \t/bin/bash  -e \t -u \t\n", 0, "/bin/bash|-e|-u"},
        {"#!/usr/bin/env bash\n", 0, "/usr/bin/env|bash"},
        {"#!/usr/bin/env python3 -u -W ignore\n", 0, "/usr/bin/env|python3|-u|-W|ignore"},
        {"#!/bin/sh\r\n", 0, "/bin/sh\r"},
        {"#!/bin/sh -x\r\n", 0, "/bin/sh|-x\r"},
        {"#!/bin/sh -x \r \n", 0, "/bin/sh|-x|\r"},
        {"#!/bin/sh # a comment\n", 0, "/bin/sh"},
        {"#!/bin/sh#x\n", 0, "/bin/sh"},
        {"#!/bin/sh\n\necho\n", 0, "/bin/sh"},
        {"#!\n", 0, "NOINTERP"},
        {"#!  \t \n", 0, "NOINTERP"},
        {"#!#/bin/sh\n", 0, "NOINTERP"},
        {"#!/bin/sh", 0, "NOEOL"},
        {"#!   ", 0, "NOEOL"},
        {"#!", 0, "NOEOL"},
        {"#!/bin/sh \0 x\n", 14, "/bin/sh|"},
    };
    int fail = 0, n = 0;
    for (size_t i = 0; i < sizeof cases / sizeof cases[0]; i++, n++) {
        const struct sb_case *c = &cases[i];
        fail += check_case(c->line, c->len ? c->len : strlen(c->line), c->want, n);
    }
    /* IMG_SHSIZE boundary: a #! line of L bytes, '\n' included, puts its EOL at index L-1. */
    static const size_t lens[] = {IMG_SHSIZE - 1, IMG_SHSIZE, IMG_SHSIZE + 1};
    for (size_t i = 0; i < sizeof lens / sizeof lens[0]; i++, n++) {
        char line[IMG_SHSIZE + 2];
        size_t L = lens[i];
        memset(line, 'a', L);
        memcpy(line, "#!/", 3);
        line[L - 1] = '\n';
        line[L] = '\0';
        char want[IMG_SHSIZE + 2];
        if (L <= IMG_SHSIZE) {
            memcpy(want, line + 2, L - 3);
            want[L - 3] = '\0';
        } else {
            snprintf(want, sizeof want, "NOEOL");
        }
        fail += check_case(line, L, want, n);
    }
    static const char *const targets[][3] = {
        {"/x/stub", "jq", "/x/.stub-real/jq"},
        {"/x/stub/", "jq", "/x/.stub-real/jq"},
        {"/a/b/c", "d", "/a/b/.c-real/d"},
        {"/stub", "jq", "/.stub-real/jq"},
        {"/Users/u/.claude/bin", "cc-x", "/Users/u/.claude/.bin-real/cc-x"},
    };
    for (size_t i = 0; i < sizeof targets / sizeof targets[0]; i++, n++) {
        char out[PATH_MAX];
        if (derive_target(targets[i][0], targets[i][1], out, sizeof out) != 0 || strcmp(out, targets[i][2])) {
            fprintf(stderr, "cc-shim selftest: case %d: want [%s] got [%s]\n", n, targets[i][2], out);
            fail++;
        }
    }
    if (fail) {
        printf("cc-shim selftest: FAIL %d/%d\n", fail, n);
        return 1;
    }
    printf("cc-shim selftest: ok %d/%d\n", n, n);
    return 0;
}

int main(int argc, char **argv, char **envp, char **apple) {
    static char pbuf[PATH_MAX], dbuf[PATH_MAX], rbuf[PATH_MAX], tbuf[PATH_MAX], ibuf[PATH_MAX];
    static char vdata[IMG_SHSIZE], line[IMG_SHSIZE], hopenv[64];
    static char *tok[MAX_TOKENS];

    /* The path handed to execve, unresolved: a stub symlink keeps its own name and directory. */
    const char *P = NULL;
    for (char **a = apple; a && *a; a++)
        if (!strncmp(*a, "executable_path=", 16)) { P = *a + 16; break; }
    if (!P || !*P) {
        uint32_t sz = sizeof pbuf;
        P = (_NSGetExecutablePath(pbuf, &sz) == 0) ? pbuf : (argc > 0 ? argv[0] : "cc-shim");
    }
    const char *slash = strrchr(P, '/');
    const char *N = slash ? slash + 1 : P;

    const char *T, *argv0;
    char **args;
    int nargs;
    if (!strcmp(N, "cc-shim")) {
        if (argc == 2 && !strcmp(argv[1], "--selftest")) return selftest();
        if (argc == 2 && !strcmp(argv[1], "--version")) { printf("cc-shim %s\n", CC_SHIM_HASH); return 0; }
        fputs("usage: cc-shim --selftest | --version\n"
              "       (as a symlink named N in dir D: runs D/../.<D>-real/N; as cc-exec: cc-exec <script> [args])\n",
              stderr);
        return 64;
    } else if (!strcmp(N, "cc-exec")) {
        if (argc < 2) { fputs("usage: cc-exec <script> [args...]\n", stderr); return 64; }
        T = argv[1];
        argv0 = argv[1];
        args = argv + 2;
        nargs = argc - 2;
    } else {
        if (!slash) {
            snprintf(dbuf, sizeof dbuf, ".");
        } else if (slash == P) {
            snprintf(dbuf, sizeof dbuf, "/");
        } else if ((size_t)(slash - P) >= sizeof dbuf) {
            die(126, "%s: path too long", N);
        } else {
            memcpy(dbuf, P, (size_t)(slash - P));
            dbuf[slash - P] = '\0';
        }
        const char *D = dbuf;
        if (needs_realpath(D)) {
            if (!realpath(D, rbuf)) die(exec_rc(errno), "%s: %s: %s", N, D, strerror(errno));
            D = rbuf;
        }
        if (derive_target(D, N, tbuf, sizeof tbuf) != 0) die(126, "%s: target path too long", N);
        T = tbuf;
        argv0 = argc > 0 ? argv[0] : N;
        args = argv + 1;
        nargs = argc > 1 ? argc - 1 : 0;
    }

    /* Hop guard: a PATH-walker that lands back on a stub would exec forever in one pid. */
    long hops = 1;
    const char *h = getenv("CC_SHIM_HOPS");
    if (h) {
        char *e;
        long pid = strtol(h, &e, 10);
        if (*e == ':' && pid == (long)getpid()) {
            char *e2;
            long n = strtol(e + 1, &e2, 10);
            if (e2 != e + 1 && *e2 == '\0' && n >= 0) hops = n < MAX_HOPS ? n + 1 : MAX_HOPS + 1;
        }
    }
    if (hops > MAX_HOPS) die(126, "exec loop through %s (%d same-pid hops)", N, MAX_HOPS);
    snprintf(hopenv, sizeof hopenv, "CC_SHIM_HOPS=%ld:%ld", (long)getpid(), hops);
    size_t ec = 0;
    while (envp && envp[ec]) ec++;
    char *env2[ec + 2];
    size_t j = 0;
    for (size_t i = 0; i < ec; i++)
        if (strncmp(envp[i], "CC_SHIM_HOPS=", 13)) env2[j++] = envp[i];
    env2[j++] = hopenv;
    env2[j] = NULL;

    int fd = open(T, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        if (errno == ENOENT) die(127, "%s: no target %s", N, T);
        die(126, "%s: %s", T, strerror(errno));
    }
    /* The kernel needs +x on the script itself; keep that, or a 0644 target would start working. */
    if (access(T, X_OK) != 0) die(126, "%s: %s", T, strerror(errno));
    ssize_t n = read_head(fd, vdata, IMG_SHSIZE);
    int re = errno;
    close(fd);
    if (n < 0) die(126, "%s: %s", T, strerror(re));

    char *v[MAX_TOKENS + nargs + 3];
    int k = 0;
    if (is_macho(vdata, n)) {
        v[k++] = (char *)argv0;
        for (int i = 0; i < nargs; i++) v[k++] = args[i];
        v[k] = NULL;
        execve(T, v, env2);
        die(exec_rc(errno), "%s: %s", T, strerror(errno));
    }
    if (n < 2 || vdata[0] != '#' || vdata[1] != '!') {
        /* No #!: the kernel says ENOEXEC and execvp/the shell run it with sh. */
        v[k++] = "sh";
        v[k++] = (char *)T;
        for (int i = 0; i < nargs; i++) v[k++] = args[i];
        v[k] = NULL;
        execve("/bin/sh", v, env2);
        die(exec_rc(errno), "/bin/sh: %s", strerror(errno));
    }
    int nt = parse_shebang(vdata, line, tok);
    if (nt == SB_NOEOL) die(126, "%s: #! line has no newline in %d bytes", T, IMG_SHSIZE);
    if (nt == SB_NOINTERP) die(126, "%s: #! line names no interpreter", T);

    /* The kernel refuses an interpreter that is itself a #! script (IMGPF_INTERPRET); exec'ing it
       from here would succeed through the kernel's #! path, which is the leak. */
    char head[4];
    ssize_t hn = peek(tok[0], head, sizeof head);
    if (hn >= 2 && head[0] == '#' && head[1] == '!')
        die(126, "%s: interpreter %s is itself a #! script", T, tok[0]);

    if (nt >= 2 && !strcmp(tok[0], "/usr/bin/env") && tok[1][0] && tok[1][0] != '-' &&
        !strchr(tok[1], '=') && !strchr(tok[1], '/') && path_lookup(tok[1], ibuf, sizeof ibuf) == 0) {
        /* Skip env's own exec, but only when the result is a binary: env would hand a #! or
           unformatted file to the kernel or to sh, so those keep the env route below. */
        hn = peek(ibuf, head, sizeof head);
        if (is_macho(head, hn)) {
            for (int i = 1; i < nt; i++) v[k++] = tok[i];
            v[k++] = (char *)T;
            for (int i = 0; i < nargs; i++) v[k++] = args[i];
            v[k] = NULL;
            execve(ibuf, v, env2);
            k = 0; /* lost a race with the file: let env report it */
        }
    }
    for (int i = 0; i < nt; i++) v[k++] = tok[i];
    v[k++] = (char *)T;
    for (int i = 0; i < nargs; i++) v[k++] = args[i];
    v[k] = NULL;
    execve(tok[0], v, env2);
    die(exec_rc(errno), "%s: %s", tok[0], strerror(errno));
}
