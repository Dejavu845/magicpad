# MagicPad genX

2026-09-24 起，当前这版叫 **MagicPad genX**。

基线 commit：`d58cfa5`（8 圈 UI loop 收工，`htmlRev=20260924-c8-h816`）。

## 编号

| 名字 | 含义 |
|---|---|
| **genX** | 基线。这一版。 |
| **genX-1** | 基线之后的第 1 次迭代 |
| **genX-2** | 第 2 次，依此类推 |

规则：

- 只在 genX 上往前加数字，不另起代号。
- 每次迭代：改 `VERSION` 的 `iteration` 和名字，打 git tag `genX-N`（本地；不 push 除非点名）。
- `htmlRev` 可以带 `genX-N`，但不要把家里 IP 写进去。
- 不绑 LLM。

产品名对外仍可写 MagicPad；对内版本一律 **genX** / **genX-N**。
