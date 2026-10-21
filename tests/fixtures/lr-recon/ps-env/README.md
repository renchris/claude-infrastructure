# ps-env — W14 (B5-R) kernel pane binding fixtures

Read by `scripts/limit-recover/lr_recon/tests/test_pane_bind_env.py`.

- `ps.txt` — the census `ps -axww -o pid=,ppid=,stat=,lstart=,args=` table. kitty 853 is the deaf
  one (its `kitten @ ls` fails); kitty 860 answers with `ls-860.json`.
  - window 7 of 853: root 900, source claude 901 (the record's birth) and target claude 905 (its
    relaunch). A test drops one of the two, never neither.
  - window 8 of 853: claude 911 whose env names `KITTY_PID=860`, a live kitty that is not its
    ancestor (the mismatch control).
  - window 9 of 853: claude 921 under the ZOMBIE root 920 (the zombie control).
  - window 3 of 860: claude 931, bound by `ls` (the healthy control). Window 4 of 860: claude 871,
    a healthy claude with a LOWER pid than every deaf one (the pid-cap ordering control).
  - 950: a headless claude under launchd, under no kitty: never judged.
- `ps-env.txt` — `ps -E -ww -o pid=,command=`: argv, then the env block. 901's argv carries a
  spoofed `KITTY_WINDOW_ID=99 KITTY_PID=860` before its env; the LAST token (the env's) wins.
- `ttys.txt` — `ps -axo pid=,tty=`.
