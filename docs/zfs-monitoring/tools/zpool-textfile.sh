#!/bin/bash
# zpool status を読み、node-exporter の textfile collector 向けのメトリクスを書く。
# 使い方: zpool-textfile.sh [出力先]（既定は /var/lib/node-exporter/zpool.prom）
# メトリクスの形式は docs/zfs-monitoring/runbook-zpool-textfile.md を参照。
# テスト用に、環境変数 ZPOOL で zpool のコマンドを、NOW で書き込む時刻を差し替えられる。

set -euo pipefail
export LC_ALL=C

out=${1:-/var/lib/node-exporter/zpool.prom}
zpool=${ZPOOL:-zpool}
now=${NOW:-$(date +%s)}

# zpool status が失敗したら何も書かない（last_run が古くなることで気づけるようにする）
status=$("$zpool" status -P -p)

tmp=$(mktemp "${out}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

awk -v now="$now" '
function esc(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    return s
}
function add(name, labels, value) {
    if (!(name in count)) {
        count[name] = 0
    }
    samples[name, ++count[name]] = name (labels == "" ? "" : "{" labels "}") " " value
}
# zfs_nicebytes の表記（0B、512B、1.50M など。1024 進）をバイト数にする
function bytes(s,    n, u, i) {
    u = substr(s, length(s), 1)
    if (u == "B") {
        s = substr(s, 1, length(s) - 1)
        u = substr(s, length(s), 1)
    }
    i = index("KMGTPE", u)
    if (i > 0) {
        s = substr(s, 1, length(s) - 1)
    }
    n = s + 0
    while (i-- > 0) {
        n *= 1024
    }
    return sprintf("%d", n)
}
# ctime の表記（Sun Oct 11 08:12:31 2026）を Unix 時刻にする
function epoch(s,    cmd, t) {
    if (s !~ /^[A-Za-z0-9 :]+$/) {
        return ""
    }
    cmd = "date -d \"" s "\" +%s"
    t = ""
    cmd | getline t
    close(cmd)
    return t
}
function pool_done() {
    if (pool == "") {
        return
    }
    add("zpool_scrub_in_progress", "zpool=\"" esc(pool) "\"", in_progress)
    if (scrub_end != "") {
        add("zpool_scrub_last_end_timestamp_seconds", "zpool=\"" esc(pool) "\"", scrub_end)
        add("zpool_scrub_last_repaired_bytes", "zpool=\"" esc(pool) "\"", scrub_repaired)
        add("zpool_scrub_last_errors", "zpool=\"" esc(pool) "\"", scrub_errors)
    }
    if (data_errors != "") {
        add("zpool_data_errors", "zpool=\"" esc(pool) "\"", data_errors)
    }
}

$1 == "pool:" {
    pool_done()
    pool = $2
    in_config = 0
    in_progress = 0
    scrub_end = scrub_repaired = scrub_errors = data_errors = ""
    next
}
$1 == "scan:" {
    if ($0 ~ /scan: scrub (in progress|paused) since /) {
        in_progress = 1
    } else if (match($0, /scan: scrub repaired [^ ]+ in .* with [0-9]+ errors on /)) {
        split(substr($0, RSTART, RLENGTH), w, " ")
        scrub_repaired = bytes(w[4])
        scrub_errors = w[length(w) - 2]
        scrub_end = epoch(substr($0, RSTART + RLENGTH))
    }
    next
}
$1 == "config:" {
    in_config = 1
    next
}
$1 == "errors:" {
    in_config = 0
    if ($0 ~ /errors: No known data errors/) {
        data_errors = 0
    } else if ($3 == "data" && $2 ~ /^[0-9]+$/) {
        data_errors = $2
    }
    next
}
in_config && NF >= 2 && $1 != "NAME" {
    labels = "zpool=\"" esc(pool) "\",vdev=\"" esc($1) "\""
    add("zpool_vdev_state", labels ",state=\"" esc(tolower($2)) "\"", 1)
    if ($3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/) {
        add("zpool_vdev_errors", labels ",type=\"read\"", $3)
        add("zpool_vdev_errors", labels ",type=\"write\"", $4)
        add("zpool_vdev_errors", labels ",type=\"checksum\"", $5)
    }
}
END {
    pool_done()
    add("zpool_textfile_last_run_timestamp_seconds", "", now)
    help["zpool_textfile_last_run_timestamp_seconds"] = "Unix time when zpool-textfile last wrote this file."
    help["zpool_vdev_state"] = "State of the pool or vdev as shown by zpool status (1 for the shown state)."
    help["zpool_vdev_errors"] = "READ, WRITE and CKSUM error counts of the pool or vdev as shown by zpool status."
    help["zpool_scrub_in_progress"] = "Whether a scrub is in progress or paused (1) or not (0)."
    help["zpool_scrub_last_end_timestamp_seconds"] = "Unix time when the last completed scrub ended."
    help["zpool_scrub_last_repaired_bytes"] = "Bytes repaired by the last completed scrub."
    help["zpool_scrub_last_errors"] = "Errors found by the last completed scrub."
    help["zpool_data_errors"] = "Number of data errors reported by zpool status."
    n = split("zpool_textfile_last_run_timestamp_seconds zpool_vdev_state zpool_vdev_errors zpool_scrub_in_progress zpool_scrub_last_end_timestamp_seconds zpool_scrub_last_repaired_bytes zpool_scrub_last_errors zpool_data_errors", order, " ")
    for (i = 1; i <= n; i++) {
        name = order[i]
        if (!(name in count)) {
            continue
        }
        print "# HELP " name " " help[name]
        print "# TYPE " name " gauge"
        for (j = 1; j <= count[name]; j++) {
            print samples[name, j]
        }
    }
}
' <<<"$status" > "$tmp"

chmod 0644 "$tmp"
mv "$tmp" "$out"
trap - EXIT
