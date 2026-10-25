# devfs-canary.pl -- repeat the exact work ttyname()/devname() does, without ever blocking the caller.
#
# Run as:  /usr/bin/perl devfs-canary.pl <state-dir> [timeout_s=3]     (never via #!: DESIGN I1)
# Prints ONE line (key=value) and exits within timeout_s + ~0.1 s, whatever the kernel does.
#   verdict=OK wall_ms=<ms> done n=<entries> scan_ms=<ms> worst_ms=<ms> worst=<name>        rc 0
#   verdict=WEDGED pid=<child> after_s=<t> last="lstat <name>"                                rc 2
#   verdict=WEDGED_PREVIOUS pid=<child> stuck_s=<s> last="lstat <name>"                       rc 3
#
# Why this shape (Confirmed from source, mac-forensics.md §2):
#   * libc devname_r() = opendir("/dev") + lstat() of EVERY entry until st_rdev matches. zsh init_io
#     -> ttyname -> devname_r is the incident stack (zsh-sample.txt:25-31). This canary repeats it,
#     and the progress file names the entry it is stuck on.
#   * A thread blocked in devfs (msleep in devfs_dntovn / vnode_getiocount) is in an UNINTERRUPTIBLE
#     wait: SIGALRM/SIGKILL do not take effect until the syscall returns, so `alarm N; exec` does
#     not bound a caller. The WORK runs in a forked child writing progress to a FILE; the parent
#     owns the alarm, never waitpid()s past it, and exits. A wedged child is ABANDONED, never killed
#     (DESIGN I9: canaries are abandoned).
#   * At most ONE wedged child may exist. The mutex is a (pid, lstart, kern.bootsessionuuid) record
#     in a boot-scoped dir: a pidfile from a previous boot, or one whose pid was reused by another
#     process (lstart differs), is stale and broken, never reported as WEDGED (DESIGN C3 drift fix).
#   * lstart is read with a raw __sysctl(KERN_PROC_PID) syscall: no ps, no fork.
#
# Test seams: CC_FX_DEV_DIR (walk this dir instead of /dev) · CC_FX_CANARY_STALL_AT=<name> (the
# child sleeps CC_FX_CANARY_STALL_S, default 30, at that entry, the shape of a devfs wedge) ·
# CC_FX_BOOT (boot uuid; else read from sysctl into a file).
use strict;
use warnings;
use POSIX qw(_exit setsid);
use Time::HiRes qw(time);

my ($dir, $tmo) = @ARGV;
$tmo ||= 3;
die "usage: perl devfs-canary.pl <state-dir> [timeout_s]\n" unless $dir && -d $dir;
my $dev = $ENV{CC_FX_DEV_DIR} || '/dev';

sub slurp_last {
    my ($f) = @_;
    my $last = '';
    if (open my $p, '<', $f) { while (<$p>) { $last = $_ } close $p }
    chomp $last;
    return $last;
}

# kernel p_starttime.tv_sec of PID, or 0 when the pid does not exist
sub pid_lstart {
    my ($pid) = @_;
    my $mib = pack('i4', 1, 14, 1, $pid);
    my $buf = "\0" x 648;
    my $len = pack('Q', 648);
    my $r = syscall(202, $mib, 4, $buf, $len, 0, 0);
    return 0 if $r != 0 || unpack('Q', $len) < 648;
    return unpack('q', substr($buf, 0, 8));
}

sub boot_uuid {
    return $ENV{CC_FX_BOOT} if $ENV{CC_FX_BOOT};
    my $f = "$dir/.bootuuid.$$";
    my $k = fork;
    return 'unknown-boot' unless defined $k;
    if (!$k) {
        open STDIN, '<', $f;    # absent file: stdin closed, never /dev/null (no devfs lookup)
        open STDOUT, '>', $f; open STDERR, '>', "$f.err";
        exec('/usr/sbin/sysctl', '-n', 'kern.bootsessionuuid') or _exit(127);
    }
    eval { local $SIG{ALRM} = sub { die "t\n" }; alarm 2; waitpid($k, 0); alarm 0 };
    my $u = slurp_last($f);
    unlink $f, "$f.err";
    return $u =~ /^[0-9A-F-]{36}$/i ? $u : 'unknown-boot';
}

my $boot = boot_uuid();
my $bdir = "$dir/canary-$boot";
mkdir $bdir unless -d $bdir;
my $pidf = "$bdir/canary.pid";
my $prog = "$bdir/canary.progress";
my $t0 = time;
my $broke = 0;

if (open my $fh, '<', $pidf) {
    my ($opid, $olst, $oboot, $ots) = split ' ', (<$fh> // '');
    close $fh;
    if ($opid && $oboot && $oboot eq $boot && kill(0, $opid) && pid_lstart($opid) == ($olst || -1)) {
        my $last = slurp_last($prog);
        printf "verdict=WEDGED_PREVIOUS pid=%d stuck_s=%d last=\"%s\"\n", $opid, $t0 - ($ots || $t0), $last;
        exit 3;
    }
    unlink $pidf;    # previous boot, dead holder or reused pid: stale, broken
    $broke = 1;
}

open my $pf, '>', $prog or die "progress: $!";
close $pf;
my $kid = fork;
die "fork: $!" unless defined $kid;
if (!$kid) {
    open my $o, '>>', $prog or _exit(9);
    select((select($o), $| = 1)[0]);
    print $o "opendir\n";
    opendir(my $d, $dev) or do { print $o "opendir_fail $!\n"; _exit(2) };
    my @e = readdir $d;
    closedir $d;
    my $tr = time;
    printf $o "readdir n=%d ms=%.2f\n", scalar(@e), ($tr - $t0) * 1000;
    my ($worst, $wn) = (0, '');
    my $stall = $ENV{CC_FX_CANARY_STALL_AT} // '';
    for my $n (@e) {
        next if $n eq '.' || $n eq '..';
        print $o "lstat $n\n";
        if ($stall ne '' && $n eq $stall) { sleep($ENV{CC_FX_CANARY_STALL_S} || 30) }
        my $a = time;
        lstat("$dev/$n");
        my $dt = time - $a;
        ($worst, $wn) = ($dt, $n) if $dt > $worst;
    }
    printf $o "done n=%d scan_ms=%.2f worst_ms=%.3f worst=%s\n", scalar(@e), (time - $tr) * 1000,
        $worst * 1000, $wn;
    _exit(0);
}
{
    my $tmp = "$pidf.tmp.$$";
    open my $w, '>', $tmp or die "pidfile: $!";
    printf $w "%d %d %s %d\n", $kid, pid_lstart($kid), $boot, $t0;
    close $w;
    rename $tmp, $pidf;
}
my $done = 0;
eval {
    local $SIG{ALRM} = sub { die "t\n" };
    alarm $tmo;
    waitpid($kid, 0);
    $done = 1;
    alarm 0;
};
my $last = slurp_last($prog);
if ($done) {
    unlink $pidf;
    printf "verdict=OK wall_ms=%.1f broke_stale=%d %s\n", (time - $t0) * 1000, $broke, $last;
    exit 0;
}
# Deadline passed: the child is (probably) in an uninterruptible devfs wait. Abandon it, never
# kill it, and leave the pidfile so the next run reports instead of spawning a second victim.
printf "verdict=WEDGED pid=%d after_s=%d last=\"%s\"\n", $kid, $tmo, $last;
exit 2;
