#!/usr/bin/perl
# tui-emit.pl — the rate-controlled emission loop behind scripts/tui-load.sh.
#
# WHY THIS IS NOT IN THE BASH SCRIPT. Delivering an IDENTICAL load to each candidate terminal is the
# whole basis of the comparison, and bash on macOS cannot do it:
#   · bash 3.2.57 (what macOS ships) rejects a fractional `read -t`, so the forkless builtin delay
#     is unavailable — it fails instantly and silently, turning the loop into a busy spin measured
#     at 7,651 fps against a requested 10.
#   · The `sleep` fallback costs one fork per frame, and fork latency RISES WITH LOAD. Measured on
#     this box at loadavg 13.6: requested 5 fps delivered 3.33, requested 10 delivered 9.0. That is
#     not a constant offset that cancels between candidates — load is precisely what differs
#     between a terminal that keeps up and one that does not, so the generator would hand the
#     struggling terminal a LIGHTER load and flatter its numbers. A self-flattering instrument.
#   · Deadline-corrected Time::HiRes in perl, same box, same loadavg: 10.00 fps exactly, zero forks
#     after start-up, ~5 MB RSS per pane. /usr/bin/perl is present on every macOS.
#
# DEADLINE CORRECTION, not fixed sleeps. Each frame's target is t0 + n/fps computed from the ORIGIN,
# so a slow frame is absorbed by the next sleep instead of accumulating. A fixed `sleep 1/fps` loop
# drifts monotonically and the drift is exactly proportional to how busy the terminal is.
#
# Frames arrive precomputed and NUL-separated: this process performs no string building in the hot
# loop, so what it measures is the TERMINAL's cost, not its own.
#
# ARGS: <framefile> <fps> <duration_s> <resultfile>
# Writes to <resultfile>:  frames=<n> bytes=<n> elapsed=<float>
# so the caller reports what was ACTUALLY delivered rather than what was requested.

use strict;
use warnings;
use Time::HiRes qw(time sleep);

my ($framefile, $fps, $duration, $resultfile) = @ARGV;
die "usage: tui-emit.pl <framefile> <fps> <duration> <resultfile>\n"
    unless defined $framefile && defined $fps && defined $duration && defined $resultfile;
$fps = 1 unless $fps > 0;

open(my $fh, '<', $framefile) or die "tui-emit: cannot read $framefile: $!\n";
binmode $fh;
local $/ = "\0";
my @frames = map { my $f = $_; $f =~ s/\0\z//; $f } <$fh>;
close $fh;
die "tui-emit: no frames in $framefile\n" unless @frames;

$| = 1;                       # unbuffered: a buffered writer would batch frames and destroy the rate

my $frames_sent = 0;
my $bytes_sent  = 0;
my $t0          = time;
my $deadline    = $t0 + $duration;

# Report whatever was delivered even on SIGTERM/SIGINT — a run killed early must still yield its
# numbers, or the diagnostic is emptiest exactly when something went wrong.
my $finish = sub {
    my $elapsed = time - $t0;
    $elapsed = 0.0001 if $elapsed <= 0;
    if (open(my $rf, '>', $resultfile)) {
        printf $rf "frames=%d bytes=%d elapsed=%.3f\n", $frames_sent, $bytes_sent, $elapsed;
        close $rf;
    }
    exit 0;
};
$SIG{TERM} = $SIG{INT} = $finish;

while (time < $deadline) {
    my $frame = $frames[$frames_sent % scalar(@frames)];
    print $frame;
    $bytes_sent += length($frame);
    $frames_sent++;

    # Target computed from the ORIGIN, so slow frames do not accumulate drift.
    my $target = $t0 + $frames_sent / $fps;
    my $gap    = $target - time;
    sleep($gap) if $gap > 0;
}

$finish->();
