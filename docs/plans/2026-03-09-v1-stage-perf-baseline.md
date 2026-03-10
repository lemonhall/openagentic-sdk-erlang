# V1 Stage Performance Baseline

日期：2026-03-09

## Command

`powershell
./scripts/case-governance-perf-baseline.ps1 -CaseCount 100 -TasksPerCase 5 -MailPerCase 10 -UnreadPerCase 5 -JsonOut .tmp\perf\v1-target-baseline.json
`

## Dataset

- cases: 100
- tasks per case: 5
- total tasks: 500
- mail per case: 10
- unread per case: 5
- total mail: 1000
- target case: perf_case_100
- data root: e:/development/openagentic-sdk-erlang/.tmp/perf/1

## Observed Timings

- get_case_overview/2 on one hot case: 16.691 ms
- list_inbox/2 with status=unread across all cases: 430.489 ms
- openagentic_case_scheduler_due_scan:scan_once/1 across all cases/tasks: 1193.574 ms

## Observed Counts

- overview task count: 5
- overview mail count: 10
- inbox unread count: 500
- scheduler triggered runs: 0
- scheduler skipped count: 0

## Interpretation

- 这次基线覆盖了审计里要求的 100 case / 500 task / 1000 mail 量级。
- overview 已经明显受益于索引优先读取；单案卷读取仍然保持在双位数毫秒级。
- inbox unread 虽然不再逐案卷全扫 mail 文件，但全局 inbox 仍要遍历 case 列表并做装饰，因此在 100 case 量级下已经来到数百毫秒级。
- scheduler scan_once 本次数据全部使用 manual schedule，因此测到的是“扫描/读取/评估”开销，不包含真正的运行时调用成本；当前约 1.19s，说明下一步若继续放量，最值得做的是“减少全量 task 扫描”。

## Limitations

- 本基线是本机 Windows 11 + PowerShell + Erlang/OTP 28 的单次观测，不是 CI 稳定门限。
- scheduler 本轮没有模拟大量 due job 执行，只测了 scan/eval 路径。
- 数据集为 synthetic JSON，对磁盘碎片、真实 artifacts 体积、并发 Web SSE 连接都未建模。

## Next Suggestions

1. 给 scheduler 增加更细粒度的 due 索引/候选集，避免每次 scan_once 全扫 500+ task。
2. 给全局 inbox 增加聚合索引或分页/增量读取，避免 100+ case 线性遍历。
3. 再补一轮“有 due job + fast provider”的 scheduler baseline，以及 SSE 连接下的 soak test。