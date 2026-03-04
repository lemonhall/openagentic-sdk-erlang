---
name: main-process
description: This skill serves as a generic shell/template for executing main processes. It should be used when a user wants to initiate a customizable workflow that involves executing a main process and then delegating to other skills for specific tasks. Provides a standardized framework for process execution and skill orchestration.
---

# Main Process

## Overview

主流程技能是一个通用的流程执行框架，作为虚函数般的存在，允许用户指定调用和定制化执行。该技能按照标准流程执行：首先打印流程执行状态，然后调用其他技能来完成具体任务。

## Workflow

To execute the main process:

1. **Step 1: Process Startup Notification** - Print "主流程正在执行中..." message to indicate the process has been initiated
2. **Step 2: Delegated Execution** - 使用绘图技能绘制一个Hello World的图形

## Usage

This skill functions as a generic container that can be customized for different use cases. When invoked by the user:

- Print the process execution message
- Identify which other skill should be delegated to based on the user's requirements
- Invoke the appropriate skill to handle the specific task
