# Scheduler Candidate Index Perf Follow-up

日期：2026-03-10

## Goal

验证 scheduler 在从“active task 索引优先”进一步收口到“scheduler 候选 task 索引优先”之后，`scan_once` 的扫描成本是否继续显著下降；并补一轮“真实 due job + 快 provider”的 dispatch 基线。

## Commands

```powershell
./scripts/case-governance-perf-baseline.ps1 -CaseCount 100 -TasksPerCase 5 -ActiveTasksPerCase 5 -MailPerCase 10 -UnreadPerCase 5 -JsonOut .tmp/perf/v1-target-baseline-after-scheduler-candidates.json
./scripts/case-governance-perf-baseline.ps1 -CaseCount 100 -TasksPerCase 20 -ActiveTasksPerCase 5 -MailPerCase 10 -UnreadPerCase 5 -JsonOut .tmp/perf/v1-scheduler-candidates-baseline.json
./scripts/case-governance-perf-baseline.ps1 -CaseCount 100 -TasksPerCase 20 -ActiveTasksPerCase 5 -ScheduledTasksPerCase 1 -MailPerCase 10 -UnreadPerCase 5 -ProviderMod openagentic_testing_provider_monitoring_success -JsonOut .tmp/perf/v1-scheduler-due-run-baseline.json
```

## Scenario A: Same-scale Manual Dataset

- cases: 100
- total tasks: 500
- active tasks: 500
- scheduled tasks: 0
- total mail: 1000

### Result

- 2026-03-09 pre-change `scheduler_scan_once`: `1193.574 ms`
- 2026-03-10 active-index-only `scheduler_scan_once`: `860.979 ms`
- 2026-03-10 scheduler-candidate-index `scheduler_scan_once`: `64.819 ms`
- improvement vs pre-change: `94.57%`

### Interpretation

- 这组数据说明：当 active task 实际上全是 `manual` policy 时，单靠 `tasks-by-status.json` 仍然要把 500 个 active task 全读出来逐个评估；而 `scheduler-candidates.json` 直接把候选集收敛为空后，`scan_once` 从接近 `1.2s` 直接下降到约 `65ms`。
- 这说明当前 scheduler 的主要扫描开销已经不在 case 枚举，而在“无效候选 task 的反复读取与评估”。

## Scenario B: Wide-task Manual Dataset

- cases: 100
- total tasks: 2000
- active tasks: 500
- scheduled tasks: 0
- total mail: 1000

### Result

- 2026-03-10 active-index-only `scheduler_scan_once`: `746.700 ms`
- 2026-03-10 scheduler-candidate-index `scheduler_scan_once`: `58.777 ms`
- overview: `43.724 ms`
- inbox unread: `451.174 ms`
- improvement vs active-index-only: `92.13%`

### Interpretation

- 即使总任务数扩到 2000，只要真正带 schedule policy 的 active candidate 为空，scheduler 已不再为那 500 个 active/manual task 付出线性扫描成本。
- 这也意味着当前 scheduler 的扫描性能，已经从“受 active task 总量影响明显”收口为“主要受 scheduler candidate 数量影响”。

## Scenario C: Real Due Jobs with Fast Provider

- cases: 100
- total tasks: 2000
- active tasks: 500
- scheduled tasks: 100
- total mail: 1000
- provider: `openagentic_testing_provider_monitoring_success`

### Result

- scheduler triggered runs: `100`
- scheduler skipped count: `0`
- overview: `29.491 ms`
- inbox unread: `692.326 ms`
- `scheduler_scan_once`: `40834.150 ms`

### Interpretation

- 这组数据不再是纯 scan/eval，而是“scan + dispatch + 100 次 monitoring run 执行 + 落盘”的总成本，因此数值明显上升到约 `40.8s`。
- 这证明新索引没有破坏真实调度路径；同时也把新的瓶颈暴露得很清楚：当 candidate 真正 due 时，成本主体已经转移到 run execution、session/event 落盘、report/artifact 写入与 index rebuild，而不是调度扫描本身。

## Scenario D: Real Due Jobs after Skipping Unneeded Casewide Refresh

- cases: 100
- total tasks: 2000
- active tasks: 500
- scheduled tasks: 100
- total mail: 1000
- provider: `openagentic_testing_provider_monitoring_success`
- optimization: successful non-urgent runs no longer do case-wide `refresh_case_state/2` + `rebuild_indexes/2`, and scheduler requests omit `overview`

### Result

- scheduler triggered runs: `100`
- scheduler skipped count: `0`
- overview: `15.462 ms`
- inbox unread: `304.640 ms`
- `scheduler_scan_once`: `22899.712 ms`
- improvement vs previous due-job baseline: `43.92%`

### Interpretation

- 这轮下降说明，真实 due-job 场景里一个非常重的热点就是“每次成功 run 都做整案卷 refresh/reindex”，而这在非 urgent、task 状态仍为 `active` 的成功路径上其实没有必要。
- 在当前数据集下，这一刀把 due-job 总成本从约 `40.8s` 压到约 `22.9s`；瓶颈仍然主要在 run execution / session persistence / artifact 写入，但 case-wide 写放大已经显著收口。

## Conclusion

- `scheduler-candidates.json` 这一刀是值得的：对 manual-heavy 数据集，`scan_once` 已从数百毫秒到秒级，降到稳定的几十毫秒级。
- 当前 scheduler 的扫描面已显著收口，下一步最值钱的优化不再是“继续减少 manual task 扫描”，而是：
  1. 继续拆分 run execution / session persistence / artifact promote 的性能剖面；
  2. 如有需要，再把 `next_due_at` 前移进索引，减少 interval/fixed-times 的重复评估；
  3. 只在真正改变 mail/status 聚合时才触发更重的 case-wide 索引更新。

## Artifacts

- `.tmp/perf/v1-target-baseline-after-scheduler-candidates.json`
- `.tmp/perf/v1-scheduler-candidates-baseline.json`
- `.tmp/perf/v1-scheduler-due-run-baseline.json`
- `.tmp/perf/v1-scheduler-due-run-baseline-skip-casewide-refresh.json`
