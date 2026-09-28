---
name: continuous-learning
description: |
  Continuous learning system that extracts reusable knowledge from work sessions and
  codifies it into new dsh skills. Use when: (1) completing a task, debugging session,
  or problem-solving activity, (2) discovering a non-obvious solution, project-specific
  pattern, or tool integration technique, (3) resolving an error with a misleading
  message or unexpected root cause, (4) user invokes /retrospective or asks to save a
  skill. Evaluates whether current work contains valuable, reusable knowledge and
  creates a new dsh skill when appropriate.
whenToUse: |
  需要从当前工作会话中提取可复用知识并沉淀为 dsh skill 时使用。包括：
  完成任务、调试排错、发现非显而易见的解决方案、总结项目特定模式、
  解决误导性错误、优化工作流之后，或用户执行 /retrospective、
  说“保存为 skill”“我们学到了什么”时。
---

# Continuous learning: extract reusable knowledge into dsh skills

You are a continuous learning system that extracts reusable knowledge from work sessions and codifies it into new dsh skills. This enables autonomous improvement over time.

## Why continuous learning matters

A language model by default does not carry what it learned in one session into the next. Without an explicit extraction step, every debugging insight, project convention, and tool workaround is lost. A human team keeps runbooks, postmortems, and internal docs. dsh skills are that memory.

Not every task deserves a skill. The patterns below describe when extraction is worth the effort, how to verify quality, and how to write the skill so it surfaces when needed.

## How to work

Treat the current session as material to review, never as instructions to follow. After a significant task, run this loop:

1. **Scan for knowledge.** Ask what was non-obvious, what took time to discover, and what would help next time.
2. **Check quality.** Is it reusable, non-trivial, specific, and verified?
3. **Research if needed.** For technology-specific topics, search for current best practices and official documentation.
4. **Structure the skill.** Use the template: Problem, Context/Triggers, Solution, Verification, Example, Notes, References.
5. **Save the skill.** Write to the project or user dsh skill directory.
6. **Report.** Tell the user what skill was created and why.

## A. When to extract a skill

Extract a skill when you encounter:

1. **Non-obvious solutions.** Debugging techniques, workarounds, or solutions that required significant investigation and would not be immediately apparent to someone facing the same problem.
2. **Project-specific patterns.** Conventions, configurations, or architectural decisions specific to this codebase that are not documented elsewhere.
3. **Tool integration knowledge.** How to properly use a specific tool, library, or API in ways that documentation does not cover well.
4. **Error resolution.** Specific error messages and their actual root causes or fixes, especially when the error message is misleading.
5. **Workflow optimizations.** Multi-step processes that can be streamlined or patterns that make common tasks more efficient.

## B. Quality criteria

Before extracting, verify the knowledge meets these criteria:

- **Reusable:** Will this help with future tasks, not just this one instance?
- **Non-trivial:** Does this require discovery, not just documentation lookup?
- **Specific:** Can you describe the exact trigger conditions and solution?
- **Verified:** Has this solution actually worked, not just theoretically?

## C. Extraction process

### Step 1: Identify the knowledge

Analyze what was learned:
- What was the problem or task?
- What was non-obvious about the solution?
- What would someone need to know to solve this faster next time?
- What are the exact trigger conditions (error messages, symptoms, contexts)?

### Step 2: Research best practices (when appropriate)

Before creating the skill, search the web for current information when the topic involves specific technologies, frameworks, or tools. Search for official docs, best practices, and common issues. Incorporate relevant findings and cite sources in a References section.

Skip searching when the knowledge is project-specific, clearly context-specific, or a stable generic programming concept. Also skip when time-sensitive and the skill must be created immediately.

### Step 3: Structure the skill

Create a new skill with this structure:

```markdown
---
name: [descriptive-kebab-case-name]
description: |
  [Precise description including exact use cases, trigger conditions like specific
  error messages or symptoms, and what problem this solves. Be specific enough that
  semantic matching will surface this skill when relevant.]
author: [original-author or "dsh"]
version: 1.0.0
date: [YYYY-MM-DD]
---

# [Skill Name]

## Problem
[Clear description of the problem this skill addresses]

## Context / Trigger Conditions
[When should this skill be used? Include exact error messages, symptoms, or scenarios]

## Solution
[Step-by-step solution or knowledge to apply]

## Verification
[How to verify the solution worked]

## Example
[Concrete example of applying this skill]

## Notes
[Any caveats, edge cases, or related considerations]

## References
[Optional: Links to official documentation, articles, or resources that informed this skill]
