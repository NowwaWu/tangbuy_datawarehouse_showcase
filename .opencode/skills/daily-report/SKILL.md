---
name: daily-report
description: Generate business-oriented daily and weekly reports from technical work logs. Use whenever the user wants to write a daily report, weekly report, summarize today's work, report project progress, or report data warehouse migration progress. Also use when the user mentions summarizing work, reporting to leadership, or translating technical tasks into business value.
---

# Business-Oriented Daily Report Generator

Translate technical developer work logs into business-value reports that non-technical leadership can understand.

## Core Principles

1. **De-technicalize**: Never say "built DWD layer model". Say "delivered the data foundation for X business dashboard". Translate all technical implementation into business value or requirement progress.
2. **Progress focus**: Leaders care about progress. Use terms like "XX% complete", "in testing", "expected to go live on X date".
3. **Interactive verification**: Never fabricate. If user input lacks business context, tomorrow's plan, or blockers — ask before generating.

## Fixed Template

```markdown
**一、今日工作**
需求开发 / 优化 / 进度：
问题排查 / BUG 修复：
对接沟通（产品 / 测试 / 业务 / 技术）：
文档整理 / 流程梳理：

**二、工作阻塞点**
问题：
影响范围：
期望协助：

**三、明日规划**
优先级高：
常规推进：
```

## Workflow

### Step 1: Diagnose & Ask
After receiving the user's work log, do NOT immediately generate the report. First assess:
- What business requirement does each technical action (build table, modify code) support?
- Who was communicated with, and what business logic was being confirmed?
- Are there any blockers today? (User didn't mention — ask)
- What are tomorrow's high-priority business objectives?

Ask 2-3 core questions if needed. Example:
> "Got it! To help leadership understand and appreciate your work, let me confirm a few things:
> 1. The 'order table' you built today — which specific business requirement or dashboard does it support? What's the progress percentage?
> 2. Any blockers today that need coordination? If none, I'll mark it as none.
> 3. What's the highest priority business item for tomorrow?"

### Step 2: Translate & Generate
After user answers, combine initial info and supplementals, output strictly following the Fixed Template.

Translation example: "Ran the sales dashboard base table today" → "需求开发 / 优化 / 进度：【Sales Dashboard Requirement】Core data model development complete, overall progress 80%, entering data validation phase."

If a category truly has nothing, write "无" — do not delete template sections.

### Step 3: Auto Commit to GitHub
After generating the report, automatically:
1. `git add -A`
2. `git commit -m "chore: daily report — YYYY-MM-DD"` (use today's date)
3. `git push`

This step requires no user confirmation. Execute automatically after report output.
