#!/usr/bin/env bats
# zpool-textfile.sh のテスト。`bats docs/zfs-monitoring/tools/test` で実行する。
# zpool は偽物（fixtures の出力を返すスクリプト）に差し替える。

setup() {
    TOOLS="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FIXTURES="$BATS_TEST_DIRNAME/fixtures"
    SCRIPT="$TOOLS/zpool-textfile.sh"
    OUT_DIR="$BATS_TEST_TMPDIR/textfile"
    mkdir -p "$OUT_DIR"
    OUT="$OUT_DIR/zpool.prom"
    FAKE_ZPOOL="$BATS_TEST_TMPDIR/zpool"
    export TZ=UTC NOW=1800000000 ZPOOL="$FAKE_ZPOOL"
}

# fixture の内容を返す偽の zpool を作る。引数は $BATS_TEST_TMPDIR/args に残す。
fake_zpool() {
    cat > "$FAKE_ZPOOL" <<EOF
#!/bin/bash
echo "\$*" > "$BATS_TEST_TMPDIR/args"
cat "$FIXTURES/$1.txt"
exit ${2:-0}
EOF
    chmod +x "$FAKE_ZPOOL"
}

assert_fixture() {
    fake_zpool "$1"
    run "$SCRIPT" "$OUT"
    [ "$status" -eq 0 ]
    diff -u "$FIXTURES/$1.prom" "$OUT"
}

@test "ONLINE（braque の実際の出力）" {
    assert_fixture online
}

@test "DEGRADED: FAULTED と UNAVAIL の vdev、行末の注記、エラー数" {
    assert_fixture degraded
}

@test "scrub の進行中は in_progress=1 で、前回の結果は出さない" {
    assert_fixture scrub-in-progress
}

@test "scrub の一時停止も in_progress=1" {
    assert_fixture scrub-paused
}

@test "scrub でエラーあり: 修復量の単位の換算、日をまたぐ所要時間、data errors の件数" {
    assert_fixture scrub-errors
}

@test "複数のプール、logs / cache / spares、resilver の完了と scan なし" {
    assert_fixture multi-pool
}

@test "プールが無いときは last_run だけ書く" {
    assert_fixture no-pools
}

@test "zpool status -P -p で呼ぶ" {
    fake_zpool online
    run "$SCRIPT" "$OUT"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/args")" = "status -P -p" ]
}

@test "zpool status が失敗したら、既存のファイルを書き換えずに失敗する" {
    echo "old" > "$OUT"
    fake_zpool online 1
    run "$SCRIPT" "$OUT"
    [ "$status" -ne 0 ]
    [ "$(cat "$OUT")" = "old" ]
    [ "$(ls -A "$OUT_DIR")" = "zpool.prom" ]
}

@test "一時ファイルを残さず、node-exporter が読める権限で置く" {
    fake_zpool online
    run "$SCRIPT" "$OUT"
    [ "$status" -eq 0 ]
    [ "$(ls -A "$OUT_DIR")" = "zpool.prom" ]
    [ "$(stat -c %a "$OUT")" = "644" ]
}

@test "NOW が無ければ現在時刻を書く" {
    unset NOW
    fake_zpool no-pools
    before=$(date +%s)
    run "$SCRIPT" "$OUT"
    after=$(date +%s)
    [ "$status" -eq 0 ]
    ts=$(awk '$1 == "zpool_textfile_last_run_timestamp_seconds" { print $2 }' "$OUT")
    [ "$ts" -ge "$before" ] && [ "$ts" -le "$after" ]
}
